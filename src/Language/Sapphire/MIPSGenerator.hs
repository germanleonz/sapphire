{-# LANGUAGE LambdaCase #-}
{-|
    MIPS code generation module
 -}
module Language.Sapphire.MIPSGenerator
    ( MIPSGenerator
    , processMIPSGenerator
    ) where

import           Language.Sapphire.MIPS        as MIPS
import           Language.Sapphire.Program
import           Language.Sapphire.SappMonad   hiding (initialWriter)
import           Language.Sapphire.SymbolTable
import           Language.Sapphire.TAC         as TAC hiding (Label)

import           Control.Monad                 (liftM, unless, when, void)
import           Control.Monad.Reader          (asks)
import           Control.Monad.RWS             (RWS, execRWS, lift)
import           Control.Monad.State           (get, gets, modify)
import           Control.Monad.Writer          (tell)
import           Data.Foldable                 (concat, forM_, mapM_, toList)
import           Data.Maybe                    (fromJust)
import           Data.Sequence                 (Seq, empty, singleton)
import qualified Data.Map.Strict               as Map (Map, empty, insert,
                                                singleton, fromList, member,
                                                adjust, lookup, foldlWithKey)
import           Prelude                       hiding (EQ, LT, GT, concat,
                                                mapM_)

--------------------------------------------------------------------------------

type MIPSGenerator = RWS SappReader MIPSWriter MIPSState

--------------------------------------------------------------------------------
-- State

data MIPSState = MIPSState
    { table               :: SymbolTable
    , registerDescriptors :: RegDescriptorTable

    {-, variablesDescriptors :: -}
    }

type RegDescriptorTable = Map.Map Register RegDescriptor

initialRegDescriptors :: RegDescriptorTable
initialRegDescriptors = Map.fromList
    [ (T0, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (T1, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (T2, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (T3, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (T4, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (T5, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (T6, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (T7, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (T8, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (T9, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (S0, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (S1, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (S2, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (S3, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (S4, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (S5, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (S6, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (S7, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (A0, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (A1, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (A2, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (A3, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (V0, RegDescriptor { values = [], genPurpose = True, dirty = False })
    , (V1, RegDescriptor { values = [], genPurpose = True, dirty = False })
    ]

data RegDescriptor = RegDescriptor
    { values     :: [Reference]
    , genPurpose :: Bool
    , dirty      :: Bool
    }

{-data VarDescriptor = VarDescriptor -}
    {-{ var       :: Reference-}
    {-, locations :: Reference-}
    {-}-}

----------------------------------------
-- Instances

instance SappState MIPSState where
    getTable       = table
    putTable tab s = s { table = tab }
    getStack   = undefined
    getScopeId = undefined
    getAst     = undefined
    putStack   = undefined
    putScopeId = undefined
    putAst     = undefined

instance Show MIPSState where
    show = showSappState

----------------------------------------
-- Initial

initialState :: MIPSState
initialState = MIPSState
    { table   = emptyTable

    , registerDescriptors = initialRegDescriptors
    {-, variablesDescriptors-}
    }

--------------------------------------------------------------------------------
-- Writer

type MIPSWriter = Seq MIPS.Instruction

----------------------------------------
-- Initial

initialWriter :: MIPSWriter
initialWriter = empty

----------------------------------------

generate :: MIPS.Instruction -> MIPSGenerator ()
generate = tell . singleton

--------------------------------------------------------------------------------
-- Building the Monad

buildMIPSGenerator :: SymbolTable -> Seq TAC -> MIPSGenerator ()
buildMIPSGenerator tab blocks = do
    modify $ \s -> s { table = tab }
    tell initialWriter
    emitPreamble

    let tac = concat $ fmap toList blocks
    mapM_ tac2Mips tac

--------------------------------------------------------------------------------
-- Using the Monad

processMIPSGenerator :: SappReader -> SymbolTable -> Seq TAC -> MIPSWriter
processMIPSGenerator r s = generateMIPS r . buildMIPSGenerator s

generateMIPS :: SappReader -> MIPSGenerator a -> MIPSWriter
generateMIPS r = snd . flip (flip execRWS r) initialState

emitPreamble :: MIPSGenerator ()
emitPreamble = do
    filePath <- asks file
    generate $ MIPS.Comment $ filePath ++ " - Sapphire compiler generated MIPS code"

    --  Generate .data section
    generateGlobals

    generate $ MIPS.PutDirective ".text"
    generate $ MIPS.PutDirective ".align 2"
    generate $ MIPS.PutDirective ".globl main"

{-
 -    Generates MIPS code for printing scalar data types
 -}
generatePrintString :: Offset -> MIPSGenerator ()
generatePrintString off  = do
    generate $ Li V0 (Const 4)
    generate $ La A0 (Label ("_string" ++ show off))
    generate Syscall

generatePrint :: Reference -> MIPS.Code -> MIPSGenerator ()
generatePrint ref code  = do
    generate $ Li V0 (Const code)
    {-generate $ Lw A0 (Indexed int reg) -}
    generate Syscall

generateRead :: Reference -> MIPS.Code -> MIPSGenerator ()
generateRead ref code = do
    generate $ Li V0 (Const code)
    {-generate $ Lw A0 (Indexed int reg) -}
    generate Syscall

generateGlobals :: MIPSGenerator ()
generateGlobals = do
    generate $ MIPS.PutDirective ".data"
    syms <- gets (toSeq . getTable)
    forM_ syms $ \(idn, sym) -> do
        case sym of
            SymInfo { dataType = Lex String _ , offset = off } -> generate $ Asciiz ("_string" ++ show off) idn
            otherwise -> return ()

----------------------------------------
--  Register allocation

{-|
 -  Given a Reference, say r, of a current var or temporary,
 -  a reason (to read or to write), this function will assign
 -  a register for r according to the following rules:
 -
 -  - A register already holding r
 -  - An empty register
 -  - An unmodified register
 -  - A modified (dirty) register. We have to spill it
 -
 -}

data Reason = Read | Write
            deriving (Eq)

getRegister :: Reason -> Reference -> MIPSGenerator Register
getRegister reason ref = do
    reg <- do
        mReg <- findRegisterWithContents ref
        case mReg of
            Just reg -> return reg
            Nothing -> do
                mEmptyReg <- findEmptyRegister
                reg <- case mEmptyReg of
                    Just emptyReg -> return emptyReg
                    Nothing -> error "MIPSGenerator.getRegister: can't spill yet"

                slaveReference ref reg
                when (reason == Read) $ do
                    op <- buildOperand ref
                    -- case op of
                    --     Register ry         -> generate $ Move reg ry
                    --     immm@(Const imm)    -> generate $ Li reg immm
                    --     ind@(Indexed int r) -> generate $ Lw reg ind
                    generate $ Lw reg op
                    markClean reg
                return reg

    when (reason == Write) $ markDirty reg
    return reg

getRegisterForWrite :: Reference -> MIPSGenerator Register
getRegisterForWrite = getRegister Write

findRegisterWithContents :: Reference -> MIPSGenerator (Maybe Register)
findRegisterWithContents ref = gets registerDescriptors >>= return . Map.foldlWithKey checkRegister Nothing
        where
            checkRegister Nothing      reg regDes = if ref `elem` values regDes then Just reg else Nothing
            checkRegister reg@(Just _) _   _    = reg

findEmptyRegister :: MIPSGenerator (Maybe Register)
findEmptyRegister = gets registerDescriptors >>= return . Map.foldlWithKey checkRegister Nothing
    where
        checkRegister mReg keyReg regDes = case (mReg, values regDes) of
            (Just _, _)       -> mReg
            (Nothing, [])     -> Just keyReg
            (Nothing, values) -> Nothing

getRegDescriptor :: Register -> MIPSGenerator RegDescriptor
getRegDescriptor = flip getsRegDescriptor id

getsRegDescriptor :: Register -> (RegDescriptor -> a) -> MIPSGenerator a
getsRegDescriptor reg f = gets registerDescriptors >>= return . f . fromJust . Map.lookup reg

slaveReference :: Reference -> Register -> MIPSGenerator ()
slaveReference ref reg = do
    regDes <- gets registerDescriptors
    if Map.member reg regDes
        then modify $ \s -> s { registerDescriptors = Map.adjust (\rd -> rd { values = ref : values rd }) reg regDes }
        else error "MIPSGenerator.markDirty: marking non-existent register as dirty"

locationsAreSame :: Reference -> Reference -> MIPSGenerator ()
locationsAreSame r1 r2 = return ()

markDirty :: Register -> MIPSGenerator ()
markDirty reg = do
    regDes <- gets registerDescriptors
    if Map.member reg regDes
        then modify $ \s -> s { registerDescriptors = Map.adjust (\rd -> rd { dirty = True }) reg regDes }
        else error "MIPSGenerator.markDirty: marking non-existent register as dirty"

markClean :: Register -> MIPSGenerator ()
markClean reg = do
    regDes <- gets registerDescriptors
    if Map.member reg regDes
        then modify $ \s -> s { registerDescriptors = Map.adjust (\rd -> rd { dirty = False }) reg regDes }
        else error "MIPSGenerator.markDirty: marking non-existent register as dirty"

spillRegister :: Register -> MIPSGenerator ()
spillRegister reg = return ()

spillAllDirtyRegisters :: MIPSGenerator ()
spillAllDirtyRegisters = return ()

buildOperand :: Reference -> MIPSGenerator Operand
buildOperand = \case
    Address   _ ref glob -> do
        off <- offset
        return $ Indexed off (if glob then GP else FP)
            where
                offset = case ref of
                    Constant val -> case val of
                        ValInt int -> return int
                        _          -> error "MIPSGenerator.buildOperand: constant is not an integer"
                    _            -> error "MIPSGenerator.buildOperand: offset is not a constant"
    Constant val -> do
        case val of
            ValInt int -> return $ Const int
            _          -> error "MIPSGenerator.buildOperand: constant is not an integer"
    Temporary int -> error "MIPSGenerator.buildOperand: offset is not a constant"

{-generateLoadConstant :: Reference -> Int -> MIPSGenerator ()-}
{-generateLoadConstant dst imm = do-}
    {-reg <- getRegisterForWrite dst-}
    {-generate $ Li reg (Const imm)-}

{-generateLoadAddress :: Reference -> MIPS.Label -> MIPSGenerator ()-}
{-generateLoadAddress dst lab = do-}
    {-reg <- getRegisterForWrite dst-}
    {-generate $ La reg lab-}

----------------------------------------

tac2Mips :: TAC.Instruction -> MIPSGenerator ()
tac2Mips = \case
      TAC.Comment str -> generate $ MIPS.Comment str

      TAC.PutLabel lab str -> generate $ MIPS.PutLabel lab str

      AssignBin x op y z -> do
        ry  <- getRegister Read y
        rz  <- getRegister Read z
        rx  <- getRegister Write x

        case op of
            ADD -> generate $ Add rx ry rz
            SUB -> generate $ Sub rx ry rz
            MUL -> generate $ Mul rx ry rz
            DIV -> generate (Div ry rz) >> generate (Mflo rx)
            MOD -> generate (Div ry rz) >> generate (Mfhi rx)
            {-POW   -> "^"-}
            OR  -> generate $ Or  rx ry rz
            AND -> generate $ And rx ry rz

      AssignUn res unop op -> do
        case unop of
            NOT -> return () -- Boolean not
            NEG -> return () -- Arithmetic negation

      Assign x y -> do
        getRegister Read y
        void $ getRegister Write x


--    | AssignArrR
--    | AssignArrL
    -- Function related instructions
      BeginFunction w   -> do
        generate $ Subu  SP SP (Const 8)            -- Decrement $sp to make space to save $ra, $fp
        {-generate $ Subu  SP SP (Const 12)           -- Decrement $sp to make space to save $ra, $fp and return value-}
        generate $ Sw    FP (Indexed 8 SP)          -- Save fp
        generate $ Sw    RA (Indexed 4 SP)          -- Save ra
                                                    -- Save return value
        generate $ Addiu FP SP (Const 8)            -- Setup new fp
        when (w /= 0) . generate $ Subu SP SP (Const w)    -- Decrement sp to make space for locals/temps

      EndFunction       -> do
        return ()
        -- We could have an implicit return value here, but in our case return statements are mandatory

      PushParameter ref -> do
        generate $ Subu SP SP (Const 4)     -- Decrement sp to make space for param
        reg <- getRegister Read ref
        generate $ Sw reg (Indexed 4 SP)    -- Copy param value to stack

      PopParameters int -> do
        generate $ Addi SP SP (Const int)   -- Pop params of stack

      Return mayA     -> do
        case mayA of
            Just ref -> do
                {-Register reg <- getRegister ref-}
                generate $ Move V0 T5
                return ()
            Nothing  -> return ()
        generate $ Move SP FP               -- Pop callee frame off stack
        {-generate $ Lw FP (Indexed (-8)  FP)    -- Restore saved return value-}
        generate $ Lw RA (Indexed (-4) FP)  -- Restore saved ra
        generate $ Lw FP (Indexed 0  FP)    -- Restore saved fp
        generate $ Jr RA                    -- Return from function

      PCall lab nInt  -> do
        generate $ Jal lab

      FCall ref lab n -> do
        generate $ Jal lab
        -- get return value TO DO
        ret <- getRegister Write ref
        generate $ Move ret V0 -- Copy return value from $v0 - MIPS Convention

      -- Print
      PrintInt    ref   -> generatePrint ref 1
      PrintFloat  ref   -> return ()
      PrintChar   ref   -> return ()
      PrintBool   ref   -> return ()
      PrintString off _ -> generatePrintString off

      -- Read
      ReadInt   ref -> return ()
      ReadFloat ref -> return ()
      ReadChar  ref -> return ()
      ReadBool  ref -> return ()
      -- Goto
      Goto lab                  -> do
        spillAllDirtyRegisters
        generate $ B lab        --  Unconditional branch
      IfGoto      rel le ri lab -> do
        regLe <- getRegister Read le
        regRi <- getRegister Read ri
        case rel of
            EQ -> do
                generate $ Sub regLe regLe regRi
                generate $ Beqz regLe lab
            NE -> do
                generate $ Sub regLe regLe regRi
                generate $ Bnez regLe lab
            LT -> do
                generate $ Sub regLe regLe regRi
                generate $ Bgtz regLe lab
            LE -> do
                generate $ Sub regLe regLe regRi
                generate $ Bgez regLe lab
            GT -> do
                generate $ Sub regLe regLe regRi
                generate $ Bltz regLe lab
            GE -> do
                generate $ Sub regLe regLe regRi
                generate $ Blez regLe lab

      IfTrueGoto  ref lab       -> do
        reg <- getRegister Read ref
        generate $ Beqz reg lab
      IfFalseGoto ref lab       -> do
        reg <- getRegister Read ref
        generate $ Bnez reg lab
      _                         -> error "MIPSGenerator.tac2Mips unknown instruction"
