{-# LANGUAGE LambdaCase    #-}
{-# LANGUAGE TupleSections #-}
{-|
 - TAC Generator Monad
 -
 - This monad needs to generate the necessary intermediate representation (IR)
 - in this case the three-reference code; store it temporarily as a structure for
 - further processing and send it to a temporary file for debugging purposes.
 -}
module Language.Sapphire.TACGenerator
    ( TACGenerator
    , processTACGenerator
    ) where

import           Language.Sapphire.Program
import           Language.Sapphire.SappMonad   hiding (initialWriter)
import           Language.Sapphire.SymbolTable
import           Language.Sapphire.TAC
import           Language.Sapphire.TypeChecker (processAccessChecker,
                                                processExpressionChecker)

import           Control.Arrow                 (second, (&&&))
import           Control.Monad                 (guard, liftM, unless, void)
import           Control.Monad.RWS             (RWS, execRWS, lift)
import           Control.Monad.State           (get, gets, modify)
import           Control.Monad.Trans.Maybe     (runMaybeT)
import           Control.Monad.Writer          (tell)
import           Data.Foldable                 (foldl', forM_, mapM_, toList)
import           Data.Functor                  ((<$>))
import           Data.Maybe                    (fromJust, isJust)
import           Data.Sequence                 (Seq, empty, fromList, length,
                                                null, reverse, singleton, zip,
                                                (|>))
import           Data.Traversable              (forM, mapM)
import           Prelude                       hiding (Ordering (..), exp,
                                                length, lookup, mapM, mapM_,
                                                null, reverse, zip)

--------------------------------------------------------------------------------

type TACGenerator = RWS TACReader TACWriter TACState

--------------------------------------------------------------------------------
-- Reader

type TACReader = ()

--------------------------------------------------------------------------------
-- State

data TACState = TACState
    { table       :: SymbolTable
    , stack       :: Stack Scope
    , scopeId     :: Scope
    , ast         :: Program
    , tempSerial  :: Serial
    , labelSerial :: Serial
    , loopStack   :: Stack (Label, Label)   -- (StartLoopLabel, EndLoopLabel)
    }

----------------------------------------
-- Instances

instance SappState TACState where
    getTable   = table
    getStack   = stack
    getScopeId = scopeId
    getAst     = ast
    putTable   tab s = s { table   = tab }
    putStack   stk s = s { stack   = stk }
    putScopeId sc  s = s { scopeId = sc  }
    putAst     as  s = s { ast     = as  }

instance Show TACState where
    show = showSappState

----------------------------------------
-- Initial

initialState :: TACState
initialState = TACState
    { table       = emptyTable
    , stack       = globalStack
    , scopeId     = globalScope
    , ast         = Program empty
    , tempSerial  = 0
    , labelSerial = 0
    , loopStack   = emptyStack
    }

--------------------------------------------------------------------------------
-- Writer

type TACWriter = TAC

----------------------------------------
-- Initial

initialWriter :: TACWriter
initialWriter = empty

----------------------------------------

generate :: Instruction -> TACGenerator ()
generate = tell . singleton

--------------------------------------------------------------------------------
-- Building the Monad

buildTACGenerator :: SymbolTable -> Program -> TACGenerator ()
buildTACGenerator tab program@(Program block) = do
    modify $ \s -> s { table = tab, ast = program }
    tell initialWriter
    linearizeStatements block

--------------------------------------------------------------------------------
-- Using the Monad

processTACGenerator :: TACReader -> SymbolTable -> Program -> (TACState, Seq TAC)
processTACGenerator r s = second makeBasicBlocks . generateTAC r . buildTACGenerator s

generateTAC :: TACReader -> TACGenerator a -> (TACState, TACWriter)
generateTAC r = flip (flip execRWS r) initialState

--------------------------------------------------------------------------------
-- Monad handling

enterLoop :: Label -> Label -> TACGenerator ()
enterLoop startLoop endLoop = modify $ \s -> s { loopStack = push (startLoop, endLoop) (loopStack s) }

exitLoop :: TACGenerator ()
exitLoop = modify $ \s -> s { loopStack = pop (loopStack s) }

currentLoop :: TACGenerator (Label, Label)
currentLoop = gets (top . loopStack)

----------------------------------------

newTemporary :: TACGenerator Reference
newTemporary = do
    current <- liftM succ $ gets tempSerial
    modify $ \s -> s { tempSerial = current }
    return $ Temporary current

newLabel :: TACGenerator Label
newLabel = do
    current <- liftM succ $ gets labelSerial
    modify $ \s -> s { labelSerial = current }
    return $ "L" ++ show current

--------------------------------------------------------------------------------
-- Statements

linearizeStatements :: StBlock -> TACGenerator ()
linearizeStatements = mapM_ $ \stL -> do
    nextLabel <- newLabel
    linearizeStatement nextLabel stL
    generate $ PutLabel nextLabel $ "next statement of line " ++ show (row $ lexPosn stL)  ++ ", " ++ show (lexInfo stL)

linearizeStatement :: Label -> Lexeme Statement -> TACGenerator ()
linearizeStatement nextLabel (Lex st posn) = do
    generate $ Comment showStatement
    case st of

        StAssign accL expL ->  do
            state <- get
            let expDt = processExpressionChecker state expL
            accAddr <- getAccessReference accL

            -- When assigning a Boolean expression, use jumping code
            if expDt == Bool then do
                trueLabel  <- newLabel
                falseLabel <- newLabel
                jumpingCode expL trueLabel falseLabel

                generate $ PutLabel trueLabel $ "true label for " ++ showStatement
                generate $ Assign accAddr (Constant $ ValBool True)
                generate $ Goto nextLabel

                generate $ PutLabel falseLabel $ "false label for " ++ showStatement
                generate $ Assign accAddr (Constant $ ValBool False)

            else do
                expAddr <- linearizeExpression expL
                generate $ Assign accAddr expAddr

        StReturn mayExpL -> (=<<) (generate . Return) . runMaybeT $ do
            guard (isJust mayExpL)
            lift . linearizeExpression $ fromJust mayExpL

        StFunctionDef idnL _ block -> do
            blockWdt <- liftM fromJust $ getsSymbol (lexInfo idnL) blockWidth

            generate $ PutLabel (lexInfo idnL) $ "function name label"

            generate $ BeginFunction blockWdt
            enterScope
            linearizeStatements block
            exitScope
            generate $ EndFunction

        StProcedureCall idnL prmLs -> do
            prmAddrs <- mapM linearizeExpression (reverse prmLs)
            mapM_ (generate . PushParameter) prmAddrs
            generate $ PCall (lexInfo idnL) (length prmAddrs)
            generate $ PopParameters $ length prmAddrs

        StRead accL -> do
            state <- get
            let accDt = processAccessChecker state accL
            getAccessReference accL >>= generate . case accDt of
                Int   -> ReadInt
                Float -> ReadFloat
                Bool  -> ReadBool
                Char  -> ReadChar
                _     -> error "TACGenerator.linearizeStatement.StRead: unreadble DataType"

        StPrint expL -> do
            state <- get
            let expDt          = processExpressionChecker state expL
                LitString strL = lexInfo expL
                idn            = show $ lexInfo strL

            if expDt == String
                then getsSymbol idn (offset &&& width) >>=
                    generate . uncurry PrintString . fromJust
                else linearizeExpression expL >>= generate . case expDt of
                    Int   -> PrintInt
                    Float -> PrintFloat
                    Bool  -> PrintBool
                    Char  -> PrintChar
                    _     -> error "TACGenerator.linearizeStatement.StPrint: unprintable DataType"

        StIf expL trueBlock falseBlock -> do
            trueLabel  <- newLabel
            falseLabel <- newLabel

            jumpingCode expL trueLabel falseLabel

            generate $ PutLabel trueLabel $ "then label for " ++ showStatement
            enterScope
            linearizeStatements trueBlock
            exitScope
            generate $ Goto nextLabel

            generate $ PutLabel falseLabel $ "else label for " ++ showStatement
            enterScope
            linearizeStatements falseBlock
            exitScope

        StCase expL whnLs othrBlock -> do
            testLabel <- newLabel
            othrLabel <- newLabel

            expAddr <- linearizeExpression expL
            generate $ Goto testLabel

            whenLabels <- forM whnLs $ \(Lex (When _ whnBlock) whnP) -> do
                whnLabel <- newLabel
                generate $ PutLabel whnLabel $ "when " ++ show whnP ++ " label for " ++ showStatement

                enterScope
                linearizeStatements whnBlock
                exitScope
                generate $ Goto nextLabel

                return whnLabel

            -- Only when there is an 'otherwise'
            unless (null othrBlock) $ do
                generate $ PutLabel othrLabel $ "otherwise label for " ++ showStatement
                enterScope
                linearizeStatements othrBlock
                exitScope
                generate $ Goto nextLabel

            generate $ PutLabel testLabel $ "test label for " ++ showStatement

            -- For every when, with the block's label
            forM_ (zip whenLabels whnLs) $ \(whnLabel, Lex (When whnExpLs _) _) ->
                forM_ whnExpLs $ \whnExpL -> do
                    whnAddrs <- linearizeExpression whnExpL
                    generate $ IfGoto EQ expAddr whnAddrs whnLabel

            -- Only jump when there is an 'otherwise'
            unless (null othrBlock) . generate $ Goto othrLabel

        StLoop befBlock expL aftBlock -> do
            befLabel <- newLabel
            aftLabel <- newLabel

            generate $ PutLabel befLabel $ "before block for " ++ showStatement
            enterScope >> enterLoop befLabel nextLabel
            linearizeStatements befBlock
            exitScope

            jumpingCode expL aftLabel nextLabel

            generate $ PutLabel aftLabel $ "after block for " ++ showStatement
            enterScope
            linearizeStatements aftBlock
            exitLoop >> exitScope

            generate $ Goto befLabel

        StFor idnL expL block -> do
            condLabel  <- newLabel
            blockLabel <- newLabel
            offTemp    <- newTemporary

            enterScope >> enterLoop condLabel nextLabel

            off <- liftM fromJust $ getsSymbol (lexInfo idnL) offset

            generate $ Assign offTemp (Constant $ ValInt off)
            let idnAddr = Address (lexInfo idnL) offTemp False

            let ExpBinary _ fromExpL toExpL = lexInfo expL
            fromAddr <- linearizeExpression fromExpL
            toAddr   <- linearizeExpression toExpL

            -- Initialize the 'for' variable
            generate $ Assign idnAddr fromAddr

            generate $ PutLabel condLabel $ "condition label for " ++ showStatement
            generate $ IfGoto GT idnAddr toAddr nextLabel

            generate $ PutLabel blockLabel $ "block label for " ++ showStatement
            linearizeStatements block
            exitLoop >> exitScope

            generate $ AssignBin idnAddr ADD idnAddr (Constant $ ValInt 1)
            generate $ Goto condLabel

        StBreak    -> currentLoop >>= generate . Goto . snd
        StContinue -> currentLoop >>= generate . Goto . fst

        _ -> return ()
        -- StVariableDeclaration
        -- StStructDefinition
    where
        showStatement = "line " ++ show (row posn) ++ ", " ++ show st

--------------------------------------------------------------------------------
-- Expressions

jumpingCode :: Lexeme Expression -> Label -> Label -> TACGenerator ()
jumpingCode expL@(Lex exp _) trueLabel falseLabel = case exp of

    LitBool v -> generate $ Goto (if lexInfo v then trueLabel else falseLabel)

    ExpBinary (Lex op _) lExpL rExpL -> case op of
        OpOr  -> do
            rightLabel <- newLabel
            jumpingCode lExpL trueLabel rightLabel
            generate $ PutLabel rightLabel "right operand of `or`"
            jumpingCode rExpL trueLabel falseLabel
        OpAnd -> do
            rightLabel <- newLabel
            jumpingCode lExpL rightLabel falseLabel
            generate $ PutLabel rightLabel "right operand of `and`"
            jumpingCode rExpL trueLabel falseLabel
        _ -> if isComparable op then do
                lAddr <- linearizeExpression lExpL
                rAddr <- linearizeExpression rExpL
                generate $ IfGoto (binaryToRelation op) lAddr rAddr trueLabel
                generate $ Goto falseLabel
            else void $ linearizeExpression expL

    ExpUnary (Lex op _) unExpL -> case op of
        OpNot -> jumpingCode unExpL falseLabel trueLabel
        _     -> void $ linearizeExpression expL

    Variable accL -> do
        accAddr <- getAccessReference accL

        generate $ IfTrueGoto accAddr trueLabel
        generate $ Goto falseLabel

    _ -> error "TACGenerator.jumpingCode: should not get jumping code for non-boolean expressions"

linearizeExpression :: Lexeme Expression -> TACGenerator Reference
linearizeExpression (Lex exp _) = case exp of

    LitInt    v -> return . Constant . ValInt   $ lexInfo v
    LitFloat  v -> return . Constant . ValFloat $ lexInfo v
    LitBool   v -> return . Constant . ValBool  $ lexInfo v
    LitChar   v -> return . Constant . ValChar  $ lexInfo v
    LitString _ -> error "TACGenerator.linearizeExpression: should not get address for a String"

    Variable accL -> do
        accAddr <- getAccessReference accL

        resTemp <- newTemporary
        generate $ Assign resTemp accAddr
        return resTemp

    FunctionCall idnL prmLs -> do
        resTemp  <- newTemporary
        prmAddrs <- mapM linearizeExpression (reverse prmLs)

        mapM_ (generate . PushParameter) prmAddrs
        generate $ FCall resTemp (lexInfo idnL) (length prmAddrs)
        return resTemp

    ExpBinary (Lex op _) lExpL rExpL -> do
        lAddr <- linearizeExpression lExpL
        rAddr <- linearizeExpression rExpL
        resTemp <- newTemporary
        generate $ AssignBin resTemp (binaryToBinOperator op) lAddr rAddr
        return resTemp

    ExpUnary (Lex op _) expL -> do
        expAddr <- linearizeExpression expL
        resTemp <- newTemporary
        generate $ AssignUn resTemp (unaryToUnOperator op) expAddr
        return resTemp

--------------------------------------------------------------------------------

getAccessReference :: Lexeme Access -> TACGenerator Reference
getAccessReference accL = do
    let deepZpp                 = deepAccess $ focusAccess accL
        VariableAccess deepIdnL = lexInfo $ defocusAccess deepZpp
        deepIdn                 = lexInfo deepIdnL
    (deepScp, deepOff, deepDtL) <- liftM fromJust $ getsSymbol deepIdn (\sym -> (top $ scopeStack sym, offset sym, dataType sym))

    -- offTemp <- newTemporary
    -- generate $ Assign offTemp (Constant $ ValInt deepOff)

    offAddr <- calculateAccessOffset deepZpp (Constant $ ValInt deepOff) (lexInfo deepDtL)
    -- Checking if it is a global variable
    return $ Address deepIdn offAddr (deepScp == globalScope)

----------------------------------------

calculateAccessOffset :: AccessZipper -> Reference -> DataType -> TACGenerator Reference
calculateAccessOffset accZ offAddr dt = case defocusAccess <$> backAccess accZ of

    Just accL -> case lexInfo accL of

        ArrayAccess _ expL -> do
            let inDt = arrayInnerDataType dt

            dtWdt   <- dataTypeWidth inDt
            expAddr <- linearizeExpression expL

            -- wdtTemp <- newTemporary
            indTemp <- newTemporary
            resTemp <- newTemporary

            -- generate $ Assign wdtTemp (Constant $ ValInt dtWdt)
            generate $ AssignBin indTemp MUL expAddr (Constant $ ValInt dtWdt)
            generate $ AssignBin resTemp ADD indTemp offAddr

            calculateAccessOffset (fromJust $ backAccess accZ) resTemp (arrayInnerDataType dt)

        StructAccess _ fldIdnL -> do
            tab <- liftM (fromJust . fromJust) $ getsSymbol (toIdentifier dt) fields
            let (fldOff, fldDtL) = ((offset &&& dataType) . fromJust) $ lookup (lexInfo fldIdnL) tab

            -- fldTemp <- newTemporary
            resTemp <- newTemporary

            -- generate $ Assign fldTemp (Constant $ ValInt fldOff)
            generate $ AssignBin resTemp ADD offAddr (Constant $ ValInt fldOff)

            calculateAccessOffset (fromJust $ backAccess accZ) resTemp (lexInfo fldDtL)

        _ -> error "TACGenerator.calculateAccessOffset: unrecognized Access"

    Nothing -> return offAddr

----------------------------------------

dataTypeWidth :: DataType -> TACGenerator Width
dataTypeWidth dt = if isArray dt
    then do
        let Array inDtL sizL = dt
        inDtWdt <- dataTypeWidth $ lexInfo inDtL
        return $ inDtWdt * lexInfo sizL
    else liftM fromJust $ getsSymbol (toIdentifier dt) width

----------------------------------------

type Leader = Bool

makeBasicBlocks :: TAC -> Seq TAC
makeBasicBlocks = separateBlocks . markLeaders
    where
        separateBlocks :: Seq (Leader, Instruction) -> Seq TAC
        separateBlocks = fmap fromList . separate empty . toList
            where
                separate blcs = \case
                    []                 -> blcs
                    ((True, it) : its) -> separate (blcs |> blc) rest
                        where
                            blc  = it : (map snd $ takeWhile (not . fst) its)
                            rest = dropWhile (not . fst) its
                    _ -> error "TACGenerator.makeBasicBlocks: non-leader instruction pattern-matched"

        markLeaders :: Seq Instruction -> Seq (Leader, Instruction)
        markLeaders = markLabels . markGotos

        markGotos :: Seq Instruction -> (Seq (Leader, Instruction), [Label])
        markGotos = (\(its, lbs, _) -> (its, lbs)) . foldl' func (empty, [], True)
            where
                func (its, lbs, mrk) it = if hasGoto it
                    then (its |> (mrk, it), getLabel it : lbs, True)
                    else (its |> (mrk, it), lbs              , False)

        markLabels :: (Seq (Leader, Instruction), [Label]) -> Seq (Leader, Instruction)
        markLabels = uncurry (foldl' (flip func))
            where
                func lb = fmap $ \(mrk, it) -> (mrk || isPutLabel it && (lb == getLabel it), it)
