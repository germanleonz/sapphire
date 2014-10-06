{-# LANGUAGE LambdaCase #-}
module Language.Sapphire.Expression
    ( Expression(..)
    , Binary(..)
    , Unary(..)
    , binaryOperation
    , unaryOperation

    , Access(..)
    , AccessHistory(..)

    , AccessZipper
    --, Thread
    , focusAccess
    , defocusAccess
    --, inArrayAccess
    --, inStructAccess
    --, inAccess
    , backAccess
    , topAccess
    , deepAccess
    ) where

import           Language.Sapphire.DataType
import           Language.Sapphire.Identifier
import           Language.Sapphire.Lexeme

import           Data.Foldable                (find)
import           Data.Functor                 ((<$), (<$>))
import           Data.Maybe                   (fromJust)
import           Data.Sequence                (Seq, fromList)

data Expression
    -- Error
--    = NoExpression                              -- Only used in Parser
    -- Literals
    = LitInt    (Lexeme Int)
    | LitFloat  (Lexeme Float)
    | LitBool   (Lexeme Bool)
    | LitChar   (Lexeme Char)
    | LitString (Lexeme String)
    -- Variable
    | Variable (Lexeme Access)
    -- Function call
    | FunctionCall (Lexeme Identifier) (Seq (Lexeme Expression))
--    | LitRange  (Lexeme Range)
    -- Operators
    | ExpBinary (Lexeme Binary) (Lexeme Expression) (Lexeme Expression)
    | ExpUnary  (Lexeme Unary)  (Lexeme Expression)
    deriving (Eq, Ord, Show)

--instance Show Expression where
--    show = runPrinter . printExpression

data Binary
    = OpPlus  | OpMinus   | OpTimes | OpDivide | OpModulo | OpPower   | OpFromTo
    | OpEqual | OpUnequal | OpLess  | OpLessEq | OpGreat  | OpGreatEq
    | OpBelongs
    | OpOr    | OpAnd
    deriving (Eq, Ord)

instance Show Binary where
    show = \case
        OpPlus    -> "+"
        OpMinus   -> "-"
        OpTimes   -> "*"
        OpDivide  -> "/"
        OpModulo  -> "%"
        OpPower   -> "^"
        OpFromTo  -> ".."
        OpOr      -> "or"
        OpAnd     -> "and"
        OpEqual   -> "=="
        OpUnequal -> "/="
        OpLess    -> "<"
        OpLessEq  -> "<="
        OpGreat   -> ">"
        OpGreatEq -> ">="
        OpBelongs -> "@"

--instance Show Binary where
--    show = \case
--        OpPlus    -> "arithmetic addition"
--        OpMinus   -> "arithmetic substraction"
--        OpTimes   -> "arithmetic multiplication"
--        OpDivide  -> "arithmetic division"
--        OpModulo  -> "arithmetic Modulo"
--        OpPower   -> "arithmetic power"
--        OpFromTo  -> "range construction operator"
--        OpOr      -> "logical disjunction"
--        OpAnd     -> "logical conjunction"
--        OpEqual   -> "equal to"
--        OpUnequal -> "not equal to"
--        OpLess    -> "less than"
--        OpLessEq  -> "less than or equal to"
--        OpGreat   -> "greater than"
--        OpGreatEq -> "greater than or equal to"
--        OpBelongs -> "belongs to Range"

binaryOperation :: Binary -> (DataType, DataType) -> Maybe DataType
binaryOperation op dts = snd <$> find ((dts==) . fst) (binaryOperator op)

binaryOperator :: Binary -> Seq ((DataType, DataType), DataType)
binaryOperator = fromList . \case
    OpPlus    -> arithmetic
    OpMinus   -> arithmetic
    OpTimes   -> arithmetic
    OpDivide  -> arithmetic
    OpModulo  -> arithmetic
    OpPower   -> [ ((Int, Int), Int), ((Float, Int), Float) ]
    OpFromTo  -> [ ((Int, Int), Range) ]
    OpOr      -> boolean
    OpAnd     -> boolean
    OpEqual   -> everythingCompare
    OpUnequal -> everythingCompare
    OpLess    -> arithmeticCompare
    OpLessEq  -> arithmeticCompare
    OpGreat   -> arithmeticCompare
    OpGreatEq -> arithmeticCompare
    OpBelongs -> [ ((Int, Range), Bool) ]
    where
        arithmetic        = [((Int, Int), Int), ((Float, Float), Float)]
        boolean           = [((Bool, Bool), Bool)]
        arithmeticCompare = [((Int, Int), Bool), ((Float, Float), Bool)]
        everythingCompare = arithmeticCompare ++ boolean

data Unary = OpNegate | OpNot
    deriving (Eq, Ord)

instance Show Unary where
    show = \case
        OpNegate -> "-"
        OpNot    -> "not"

--instance Show Unary where
--    show = \case
--        OpNegate -> "arithmetic negation"
--        OpNot    -> "logical negation"

unaryOperation :: Unary -> DataType -> Maybe DataType
unaryOperation op dt = snd <$> find ((dt==) . fst) (unaryOperator op)

unaryOperator :: Unary -> Seq (DataType, DataType)
unaryOperator = fromList . \case
    OpNegate -> [(Int, Int), (Float, Float)]
    OpNot    -> [(Bool, Bool)]

--------------------------------------------------------------------------------

data Access = VariableAccess (Lexeme Identifier)
            | ArrayAccess    (Lexeme Access)     (Lexeme Expression)
            | StructAccess   (Lexeme Access)     (Lexeme Identifier)
            deriving (Eq, Ord)

instance Show Access where
    show = \case
        VariableAccess idnL      -> lexInfo idnL
        ArrayAccess    accL indL -> show (lexInfo accL) ++ "[" ++ show (lexInfo indL) ++ "]"
        StructAccess   accL fldL -> show (lexInfo accL) ++ "." ++ lexInfo fldL

{-
 - deriving the AccessHistory data
 -
 - Access        = acc
 - AccessHistory = acc'
 -
 - acc = identifier + (acc * expression) + (acc * identifier)
 - expression = A
 - identifier = B
 -
 - acc = B + (acc * A) + (acc * B)
 -
 - acc' = A + B
 -}

data AccessHistory = HistoryArray  (Lexeme Expression)
                   | HistoryStruct (Lexeme Identifier)
                   deriving (Show)

type Thread = [Lexeme AccessHistory]

type AccessZipper = (Lexeme Access, Thread)

----------------------------------------

focusAccess :: Lexeme Access -> AccessZipper
focusAccess accL = (accL, [])

defocusAccess :: AccessZipper -> Lexeme Access
defocusAccess = fst

inArrayAccess :: AccessZipper -> Maybe AccessZipper
inArrayAccess (hstL, thrd) = case lexInfo hstL of
    ArrayAccess accL idxL -> Just (accL, (HistoryArray idxL <$ hstL) : thrd)
    _                     -> Nothing

inStructAccess :: AccessZipper -> Maybe AccessZipper
inStructAccess (hstL, thrd) = case lexInfo hstL of
    StructAccess accL fldL -> Just (accL, (HistoryStruct fldL <$ hstL) : thrd)
    _                        -> Nothing

inAccess :: AccessZipper -> Maybe AccessZipper
inAccess zpp = case lexInfo $ fst zpp of
    VariableAccess _ -> Nothing
    ArrayAccess  _ _ -> inArrayAccess zpp
    StructAccess _ _ -> inStructAccess zpp

backAccess :: AccessZipper -> Maybe AccessZipper
backAccess (accL, thrd) = case thrd of
    []                        -> Nothing
    hstL@(Lex hist _) : hstLs -> case hist of
        HistoryArray  idxL -> Just (ArrayAccess  accL idxL <$ hstL, hstLs)
        HistoryStruct fldL -> Just (StructAccess accL fldL <$ hstL, hstLs)

topAccess :: AccessZipper -> AccessZipper
topAccess zpp = case snd zpp of
    []    -> zpp
    _ : _ -> topAccess $ fromJust $ backAccess zpp

deepAccess :: AccessZipper -> AccessZipper
deepAccess zpp = case lexInfo $ fst zpp of
    VariableAccess _ -> zpp
    _                -> deepAccess $ fromJust $ inAccess zpp
