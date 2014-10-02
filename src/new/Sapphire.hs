module Main where

import           Definition
import           Parser
import           SappMonad
import           SizeOffset
import           TypeChecker

import           Control.Monad             (guard, void, when)
import           Control.Monad.Trans       (liftIO)
import           Control.Monad.Trans.Maybe (runMaybeT)
import           Data.Foldable             (mapM_)
import           Data.List                 (nub)
import           Data.Sequence             (null)
import           Prelude                   hiding (mapM_, null)
import qualified Prelude                   as P (null)
import           System.Console.GetOpt     (ArgDescr (..), ArgOrder (..),
                                            OptDescr (..), getOpt, usageInfo)
import           System.Environment        (getArgs)

main :: IO ()
main = void $ runMaybeT $ do
    (flgs, args) <- liftIO arguments
    let reader = initialReader { flags = flgs }

    when (Version `elem` flgs) . liftIO $ putStrLn version
    when (Help    `elem` flgs) . liftIO $ putStrLn help

    -- Only continue if there were no 'help' or 'version' flags
    guard . not $ (Help `elem` flgs) || (Version `elem` flgs)

    input <- if P.null args
        then liftIO getContents
        else liftIO . readFile $ head args

    let (prog, plErrs) = parseProgram input
    mapM_ (liftIO . print) plErrs
    guard (null plErrs)
    -- When there are no lexer or parser errors

    let (defS, dfErrs) = processDefinition reader plErrs prog
    mapM_ (liftIO . print) dfErrs
    guard (null dfErrs)
    -- When there are no definition errors

    let (typS, tpErrs) = processTypeChecker reader dfErrs (getTable defS) (getAst defS)
    mapM_ (liftIO . print) tpErrs
    guard (null tpErrs)
    -- When there are no type checking errors

    let (sizS, szErrs) = processSizeOffset reader tpErrs (getTable typS) (getAst typS)
    liftIO $ print sizS
    mapM_ (liftIO . print) szErrs

    liftIO $ putStrLn "done."

--------------------------------------------------------------------------------
-- Flags handling

options :: [OptDescr Flag]
options =
    [ Option "h" ["help"]    (NoArg  Help)              "shows this help message"
    , Option "v" ["version"] (NoArg  Version)           "shows version number"
    , Option "W" ["Wall"]    (NoArg  AllWarnings)       "show all warnings"
    , Option "w" ["Wnone"]   (NoArg  SuppressWarnings)  "suppress all warnings"
    , Option "o" ["output"]  (ReqArg OutputFile "FILE") "specify a FILE for output of the program"
    -- Compiler flags
    --, Option "t" ["symbol-table"]   (NoArg  SuppressWarnings)  "suppress all warnings"
    --, Option "a" ["ast"]   (NoArg  SuppressWarnings)  "suppress all warnings"
    ]

help :: String
help = usageInfo "Usage: sapphire [OPTION]... [FILE]" options

version :: String
version = "sapphire 0.9"

arguments :: IO ([Flag], [String])
arguments = do
    args <- getArgs
    case getOpt Permute options args of
         (flgs,rest,[]  ) -> return (nub $ coherent flgs, rest)
         (_   ,_   ,errs) -> ioError (userError (concat errs ++ help))
    where
        coherent = foldr func []
        func flg flgs = case flg of
            Help             -> flg : flgs
            Version          -> flg : flgs
            AllWarnings      ->
                if SuppressWarnings `elem` flgs
                    then flgs
                    else flg : flgs
            SuppressWarnings ->
                if AllWarnings `elem` flgs
                    then flgs
                    else flg : flgs
            OutputFile _     -> flg : flgs
