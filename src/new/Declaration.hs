module Declaration
    ( Declaration(..)
    , Category(..)
    ) where

import           DataType
import           Identifier
import           Lexeme

data Declaration = Declaration
    { dclIdentifier :: Lexeme Identifier
    , dclDataType   :: Lexeme DataType
    , dclCategory   :: Category
    } deriving (Show)

data Category
    = CatVariable
    | CatParameter
    | CatField
    deriving (Eq)

instance Show Category where
    show CatVariable  = "variable"
    show CatParameter = "parameter"
    show CatField     = "field"