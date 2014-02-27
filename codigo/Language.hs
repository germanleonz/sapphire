module Language where

type Program = [Statement]
type VarName = String

data DataType = Void
              | Char
              | Int
              | Float
              | String
              | Range
              | Type 
              | Array DataType
              {-| Union-}
              {-| Record-}
              deriving (Eq, Show) 

data Statement = NoOp
               | Assign VarName Expression
               deriving Show

data Expression = EChar   Char
                | EInt    Int   
                | EFloat  Float 
                | EString String 
                {-| ERange  -}
                | ETrue 
                | EFalse
                | EBin  BinOp  Expression Expression DataType
                | EComp CompOp Expression Expression DataType
                | EUnOp UnOp   Expression DataType
                | EBrack Expression
                deriving (Show)

data BinOp = Add | Sub | Mul | Div | Mod | Pow | Or | And
    deriving (Eq)

instance Show OpBin where
    show Add = "'Suma'"
    show Sub = "'Resta'"
    show Mul = "'Multiplicacion'"
    show Div = "'Division'"
    show Mod = "'Modulo'"
    show Pow = "'Potenciacion'"
    show Or  = "'Disyuncion'"
    show And = "'Conjuncion'"

data CompOp = Eq | Neq | Lt | Leq | Gt | Geq 
    deriving (Eq)

instance Show CompOp where
    show Eq  = "'Igual'"
    show Neq = "'No Igual'"
    show Lt  = "'Menor que'"
    show Leq = "'Menor o igual'"
    show Gt  = "'Mayor que'"
    show Geq = "'Mayor o igual'"

data UnOp = AritNeg | BoolNeg
    deriving (Eq)

instance Show UnOp where
    show AritNeg = "'Negacion Aritmetica'"
    show BoolNeg = "'Negacion Booleana'"

{-data Function = Function Name [Argument] [Statement]                -}

-- VIEJO 

{-data ExpressionArit = LiteralInt Int-}
    {-| LiteralFloat Float-}
    {-| PlusArit ExpressionArit ExpressionArit-}
    {-deriving Show-}

{-data ExpressionBool = LiteralBool Bool-}
    {-| OrBool ExpressionBool ExpressionBool-}
    {-| AndBool ExpressionBool ExpressionBool-}
    {-| NotBool ExpressionBool-}
    {-deriving Show-}

{-data ExpressionStrn = LiteralStrn String-}
    {-deriving Show-}

-- This example comes straight from the happy documentation

--data Exp
--      = Let String Exp Exp
--      | Exp1 Exp1
--      deriving Show

--data Exp1
--      = Plus Exp1 Term
--      | Minus Exp1 Term
--      | Term Term
--      deriving Show

--data Term
--      = Times Term Factor
--      | Div Term Factor
--      | Factor Factor
--      deriving Show

--data Factor
--      = Int Int
--      | Var String
--      | Brack Exp
--      deriving Show

--eval :: [(String,Int)] -> Exp -> Int
--eval p (Let var e1 e2) = eval ((var, eval p e1): p) e2
--eval p (Exp1 e)        = evalExp1 p e
--    where
--    evalExp1 p' (Plus  e' t) = evalExp1 p' e' + evalTerm p' t
--    evalExp1 p' (Minus e' t) = evalExp1 p' e' + evalTerm p' t
--    evalExp1 p' (Term  t)    = evalTerm p' t

--    evalTerm p' (Times t f) = evalTerm p' t * evalFactor p' f
--    evalTerm p' (Div   t f) = evalTerm p' t `div` evalFactor p' f
--    evalTerm p' (Factor f)  = evalFactor p' f

--    evalFactor _  (Int i)    = i
--    evalFactor p' (Var s)    = case lookup s p' of
--                               Nothing -> error "free variable"
--                               Just i  -> i
--    evalFactor p' (Brack e') = eval p' e'