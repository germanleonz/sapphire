module Language.Sapphire.Stack
    ( Stack(..)
    , top
    , pop
    , push
    , touch

    , topStack
    , globalStack
    , langStack
    , emptyStack
    , singletonStack
    ) where

import           Language.Sapphire.Scope

import           Data.Foldable (Foldable (..))
import           Prelude       hiding (concatMap, foldr)
import qualified Prelude       as P (foldr)

newtype Stack a = Stack [a]
    deriving (Eq)

instance Show a => Show (Stack a) where
    show (Stack s) = show s

instance Functor Stack where
    fmap f (Stack s) = Stack $ map f s

instance Foldable Stack where
    foldr f b (Stack s) = P.foldr f b s

{- |
    Shows the first element in the stack, if there are any, without popping it.
-}
top :: Stack a -> a
top (Stack [])      = error "SymbolTable.top: Empty stack"
top (Stack (x : _)) = x

{- |
    Pushes an element to the stack.
-}
push :: a -> Stack a -> Stack a
push element (Stack s) = Stack $ element : s

{- |
    Pops an element from the stack.
-}
pop :: Stack a -> Stack a
pop (Stack [])      = error "SymbolTable.pop: Empty stack"
pop (Stack (_ : s)) = Stack s

{- |
    Modifies the top element in the stack.
-}
touch :: (a -> a) -> Stack a -> Stack a
touch _ (Stack [])       = Stack []
touch f (Stack (x : xs)) = Stack (f x : xs)

----------------------------------------

{- |
    The scope stack has the inital scope by default.
-}
topStack :: Stack Scope
topStack = push topScope globalStack

globalStack :: Stack Scope
globalStack = push globalScope langStack

langStack :: Stack Scope
langStack = push langScope emptyStack

emptyStack :: Stack a
emptyStack = Stack [ ]

singletonStack :: a -> Stack a
singletonStack x = Stack [ x ]
