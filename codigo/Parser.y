{
{-# OPTIONS -w #-}
module Parser( parseProgram ) where

import Control.Monad.Writer
import Data.List (find)

import Lexer
import Language
}

%name parse
%tokentype { Token }
%monad { Alex }
%lexer { lexWrap } { TkEOF }
-- Without this we get a type error
%error { happyError }

--%attributetype { Attribute a }
--%attribute value        { a }
--%attribute data_type    { DataType }
--%attribute len          { Int }

%token

        -- Language
        newline         { TkNewLine    }
        "main"          { TkMain       }
        "begin"         { TkBegin      }
        "end"           { TkEnd        }
        "return"        { TkReturn     }
        ";"             { TkSemicolon  }
        ","             { TkComma      }

        -- -- Brackets
        "("             { TkLParen     }
        ")"             { TkRParen     }
        "["             { TkLBrackets  }
        "]"             { TkRBrackets  }
        "{"             { TkLBraces    }
        "}"             { TkRBraces    }

        -- Types
        "Void"          { TkVoidType   }
        "Int"           { TkIntType    }
        "Bool"          { TkBoolType   }
        "Float"         { TkFloatType  }
        "Char"          { TkCharType   }
        "String"        { TkStringType }
        "Range"         { TkRangeType  }
        "Union"         { TkUnionType  }
        "Record"        { TkRecordType }
        "Type"          { TkTypeType   }

        -- Statements
        -- -- Declarations
        "="             { TkAssign     }
        "def"           { TkDef        }
        "as"            { TkAs         }
        "::"            { TkSignature  }
        "->"            { TkArrow      }

        -- -- In/Out
        "read"          { TkRead       }
        "print"         { TkPrint      }

        -- -- Conditionals
        "if"            { TkIf         }
        "then"          { TkThen       }
        "else"          { TkElse       }
        "unless"        { TkUnless     }
        "case"          { TkCase       }
        "when"          { TkWhen       }

        -- -- Loops
        "for"           { TkFor        }
        "in"            { TkIn         }
        ".."            { TkFromTo     }
        "do"            { TkDo         }
        "while"         { TkWhile      }
        "until"         { TkUntil      }
        "break"         { TkBreak      }
        "continue"      { TkContinue   }

        -- Expressions/Operators
        -- -- Literals
        int             { TkInt    $$  }
        "true"          { TkTrue   $$  }
        "false"         { TkFalse  $$  }
        float           { TkFloat  $$  }
        string          { TkString $$  }
        char            { TkChar   $$  }

        -- -- Num
        "+"             { TkPlus       }
        "-"             { TkMinus      }
        "*"             { TkTimes      }
        "/"             { TkDivide     }
        "%"             { TkModulo     }
        "^"             { TkPower      }

        -- -- Bool
        "or"            { TkOr         }
        "and"           { TkAnd        }
        "not"           { TkNot        }
        "@"             { TkBelongs    }
        "=="            { TkEqual      }
        "/="            { TkUnequal    }
        "<"             { TkLess       }
        ">"             { TkGreat      }
        "<="            { TkLessEq     }
        ">="            { TkGreatEq    }

        -- -- Identifiers
        varid           { TkVarId  $$  }
        typeid          { TkTypeId $$  }

-------------------------------------------------------------------------------
-- Precedence

-- Bool
%left  "or" "and"
%right "not"

-- -- Compare
%nonassoc "@"
%nonassoc "==" "/="
%nonassoc "<" "<=" ">" ">="

%nonassoc "==" "/="
%nonassoc "<" "<=" ">" ">="

-- Arithmetic
%left "+" "-"
%left "*" "/" "%"
%left ".."
%right "-"
%right "^"

%%

-------------------------------------------------------------------------------
-- Grammar

Program :: { Program }
    : StatementList         { reverse $1 }

StatementList :: { [Checker Statement] }
    : Statement                             { [$1]    }
    | StatementList Separator Statement     { $3 : $1 }

Statement :: { Checker Statement }
    :                           { return StNoop }      -- λ, no-operation
    | varid "=" Expression
        { do
            let (Right check, state, writer) = runChecker $3
            tell writer
            return $ StAssign $1 check
        }

--    -- Definitions
--    | DataType VariableList     { StDeclaration $ map (\var -> Declaration var $1) $2 }
--    --| FunctionDef               {  }
--    | "return" Expression       { StReturn $2 }

--    -- I/O
--    | "read" VariableList       { StRead  (reverse $2) }
--    | "print" ExpressionList    { StPrint (reverse $2) }

--    -- Conditional
--    | "if" ExpressionBool "then" StatementList "end"                          { StIf $2           (reverse $4) []           }
--    | "if" ExpressionBool "then" StatementList "else" StatementList "end"     { StIf $2           (reverse $4) (reverse $6) }
--    | "unless" ExpressionBool "then" StatementList "end"                      { StIf (NotBool $2) (reverse $4) []           }
--    | "unless" ExpressionBool "then" StatementList "else" StatementList "end" { StIf (NotBool $2) (reverse $4) (reverse $6) }
--    | "case" ExpressionArit CaseList "end"                                    { StCase $2 (reverse $3) []                   }
--    | "case" ExpressionArit CaseList "else" StatementList "end"               { StCase $2 (reverse $3) (reverse $5)         }

--    -- Loops
--    | "while" ExpressionBool "do" StatementList "end"          { StWhile $2           (reverse $4) }
--    | "until" ExpressionBool "do" StatementList "end"          { StWhile (NotBool $2) (reverse $4) }
--    | "for" varid "in" ExpressionRang "do" StatementList "end" { StFor $2 $4 (reverse $6)          }
--    | "break"           { StBreak }
--    | "continue"        { StContinue }

Separator
    : ";"           {}
    | newline       {}

--CaseList :: { [Case] }
--    : Case              { [$1] }
--    | CaseList Case     { $2 : $1 }

--Case :: { Case }
--    : "when" Expression "do" StatementList      { Case $2 (reverse $4) }

---------------------------------------

DataType :: { DataType }
    : "Int"         { Int }
    | "Float"       { Float }
    | "Bool"        { Bool }
    | "Char"        { Char }
    | "String"      { String }
    | "Range"       { Range }
    | "Type"        { Type }
    | "Void"        { Void }
    --| "Union" typeid
    --| "Record" typeid
--            ------------------------------ FALTA ARREGLOS

----DataTypeArray
----    : "[" DataType "]" "<-" "[" int "]"

--VariableList :: { [Variable] }
--    : varid                         { [$1]    }
--    | VariableList "," varid        { $3 : $1 }

--FunctionDef :: { Function }
--    : "def" varid "::" Signature
--    | "def" varid "(" VariableList ")" "::" Signature "as" StatementList "end" -- length(ParemeterList) == length(Signature) - 1

--Signature :: { Signature }
--    : DataType
--    | Signature "->" DataType

---------------------------------------

Binary :: { Binary }
    : "+"       { OpPlus    }
    | "-"       { OpMinus   }
    | "*"       { OpTimes   }
    | "/"       { OpDivide  }
    | "%"       { OpModulo  }
    | "^"       { OpPower   }
    | ".."      { OpFromTo  }
    | "or"      { OpOr      }
    | "and"     { OpAnd     }
    | "=="      { OpEqual   }
    | "/="      { OpUnEqual }
    | "<"       { OpLess    }
    | "<="      { OpLessEq  }
    | ">"       { OpGreat   }
    | ">="      { OpGreatEq }
    | "@"       { OpBelongs }

Unary :: { Unary }
    : "-"       { OpNegate }
    | "not"     { OpNot    }


Expression :: { Checker Expression }
    -- Variable
    : varid                         { return $ Variable $1 }
    -- Literals
    | int                           { return $ LitInt $1    }
    | float                         { return $ LitFloat $1  }
    | "true"                        { return $ LitBool $1   }
    | "false"                       { return $ LitBool $1   }
    | char                          { return $ LitChar $1   }      --- DEFINIR
    | string                        { return $ LitString $1 }

    -- Operators
    | Expression Binary Expression  { binaryM $2 $1 $3 }
    --{ ExpBinary $2 $1 $3 DataType }
    | Unary Expression              { unaryM $1 $2 }

ExpressionList :: { [Checker Expression] }
    : Expression                        { [$1]    }
    | ExpressionList Separator Expression     { $3 : $1 }


{

-------------------------------------------------------------------------------
-- Functions

binaryM :: Binary -> Checker Expression -> Checker Expression -> Checker Expression
binaryM op leftM rightM = do
    left  <- leftM
    right <- rightM
    let checking = checkBinaryType left right
    case op of
        OpOr      -> checking [(Bool,Bool,Bool)]
        OpAnd     -> checking [(Bool,Bool,Bool)]
        OpEqual   -> checking ((Bool,Bool,Bool) : numbers)
        OpUnEqual -> checking ((Bool,Bool,Bool) : numbers)
        OpFromTo  -> checking [(Int, Int, Range)]
        OpBelongs -> checking [(Int, Range, Bool)]
        otherwise -> checking numbers        -- OpPlus OpMinus OpTimes OpDivide OpModulo OpPower OpLess OpLessEq OpGreat OpGreatEq
    where
        numbers = [(Int, Int, Int), (Float, Float, Float)]
        checkBinaryType :: Expression -> Expression -> [(DataType,DataType,DataType)] -> Checker Expression
        checkBinaryType left right types = do
            let cond (l,r,_) = dataType left == l && dataType right == r
                defaultType  = (\(_,_,r) -> r) $ head types
            case find cond types of
                Just (_,_,r) -> return $ ExpBinary op left right r
                Nothing      -> putError defaultType $ "Static Error: operator " ++ show op ++ " doesn't work with arguments " ++
                                           show (dataType left) ++ ", " ++ show (dataType right) ++ "\n"

unaryM :: Unary -> Checker Expression -> Checker Expression
unaryM op operandM = do
    operand <- operandM
    let checking = checkUnaryType operand
    case op of
        OpNegate -> checking [(Int, Int), (Float, Float)]
        OpNot    -> checking [(Bool,Bool)]
    where
        checkUnaryType :: Expression -> [(DataType,DataType)] -> Checker Expression
        checkUnaryType operand types = do
            let cond (u,_)  = dataType operand == u
                defaultType = snd $ head types
            case find cond types of
                Just (_,r) -> return $ ExpUnary op operand r
                Nothing    -> putError defaultType $ "Static Error: operator " ++ show op ++ "doesn't work with arguments " ++
                                         show (dataType operand) ++ "\n"


putError :: DataType -> String -> Checker Expression
putError dt str = do
    tell [Right $ StaticError str]
    return $ ExpError dt





-------------------------------------------------------------------------------

lexWrap :: (Token -> Alex a) -> Alex a
lexWrap cont = do
    t <- alexMonadScan
    cont t

getPosn :: Alex (Int, Int)
getPosn = do
    (AlexPn _ l c,_,_,_) <- alexGetInput
    return (l,c)

happyError :: Token -> Alex a
happyError t = do
    (l,c) <- getPosn
    fail (show l ++ ":" ++ show c ++ ": Parse error on Token: " ++ show t ++ "\n")

parseProgram :: String -> Either String Program
parseProgram s = runAlex s parse

}
