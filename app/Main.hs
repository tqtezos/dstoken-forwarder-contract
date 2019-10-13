-- {-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Monad
import System.IO hiding (putStrLn)
import Data.String
import Prelude hiding (putStrLn)

-- import Data.Version (showVersion)
import Fmt (pretty, fmt, build, nameF)
import qualified Options.Applicative as Opt
import Options.Applicative.Help.Pretty (Doc, linebreak)
import qualified Data.Text.Lazy as LT

-- import Michelson.Text (MText, mkMText, mt)
-- import Paths_morley_dstoken (version)
import Tezos.Address (Address, parseAddress)
import qualified Lorentz as L
import Michelson.Analyzer (AnalyzerRes)
import Util.IO (appendFileUtf8, hSetTranslit, writeFileUtf8)
import Universum.Print
import Universum.String
import Universum.Lifted
import Universum.Exception

import qualified Lorentz.Contracts.Forwarder.DS.V1 as DS
import qualified Lorentz.Contracts.DS.V1 as DSToken

data CmdLnArgs
  = Print !(Maybe FilePath) !Bool
  | InitialStorage !Address !(L.ContractAddr DSToken.Parameter) !(Maybe FilePath)
  | Document !(Maybe FilePath)
  | Analyze

argParser :: Opt.Parser CmdLnArgs
argParser = Opt.subparser $ mconcat
  [ printSubCmd
  , initialStorageSubCmd
  , documentSubCmd
  , analyzeSubCmd
  ]
  where
    mkCommandParser commandName parser desc =
      Opt.command commandName $
      Opt.info (Opt.helper <*> parser) $
      Opt.progDesc desc

    printSubCmd =
      mkCommandParser "print"
      (Print <$> outputOption <*> onelineOption)
      "Dump DS Token Forwarder contract in the form of Michelson code"

    initialStorageSubCmd =
      mkCommandParser "initial-storage"
      (InitialStorage <$>
        addressOption "central-wallet" "Address of central wallet" <*>
        (L.ContractAddr <$> addressOption "dstoken-address" "Address of DS Token contract") <*>
        outputOption
      )
      "Dump initial storage value"

    documentSubCmd =
      mkCommandParser "document"
      (Document <$> outputOption)
      "Dump contract documentation in Markdown"

    analyzeSubCmd =
      mkCommandParser "analyze"
      (pure Analyze)
      "Analyze DS Token Forwarder contract and print information about it"

    outputOption = Opt.optional $ Opt.strOption $ mconcat
      [ Opt.short 'o'
      , Opt.long "output"
      , Opt.metavar "FILEPATH"
      , Opt.help "Output file"
      ]

    onelineOption = Opt.switch (
      Opt.long "oneline" <>
      Opt.help "Force single line output")

-- Copy-pasted from `morley` CLI parsing.
addressOption :: String -> String -> Opt.Parser Address
addressOption name hInfo =
  Opt.option (Opt.eitherReader parseAddrDo) $ mconcat
  [ Opt.long name
  , Opt.metavar "ADDRESS"
  , Opt.help hInfo
  ]
  where
    parseAddrDo addr =
      either (Left . mappend "Failed to parse address: " . pretty) Right $
      parseAddress $ toText addr

programInfo :: Opt.ParserInfo CmdLnArgs
programInfo = Opt.info (Opt.helper <*> argParser) $ -- versionOption <*>
  mconcat
  [ Opt.fullDesc
  , Opt.progDesc "CLI for DS Token Forwarder contract"
  , Opt.header "DS Token Forwarder"
  , Opt.footerDoc usageDoc
  ]
  where
    -- versionOption = Opt.infoOption ("morley-dstoken-contract" <> showVersion version)
    --   (Opt.long "version" <> Opt.help "Show version.")

usageDoc :: Maybe Doc
usageDoc = Just $ mconcat
   [ "You can use help for specific COMMAND", linebreak
   , "EXAMPLE:", linebreak
   , "  morley-dstoken-forwarder-contract print --help", linebreak
   ]

main :: IO ()
main = do
  hSetTranslit stdout
  hSetTranslit stderr
  cmdLnArgs <- Opt.execParser programInfo
  run cmdLnArgs `catchAny` (die . displayException)
  where
    printFunc
      :: (Print text, IsString text, Monoid text)
      => (FilePath -> text -> IO ())
      -> Maybe FilePath
      -> text
      -> IO ()
    printFunc writeToFile = maybe putStrLn (\file -> writeToFile file . flip mappend "\n")
    writeFunc = printFunc writeFileUtf8
    appendFunc :: (Print text, IsString text, Monoid text) => Maybe FilePath -> text -> IO ()
    appendFunc = printFunc appendFileUtf8

    run :: CmdLnArgs -> IO ()
    run = \case
      Print mOutput forceOneline ->
        writeFunc mOutput $
          L.printLorentzContract forceOneline DS.forwarderCompilationWay DS.forwarderContract
      InitialStorage centralWalletAddr dsTokenAddr mOutput -> do
        writeFunc mOutput $ L.printLorentzValue True $ DS.Storage dsTokenAddr centralWalletAddr
      -- Document mOutput -> do
      --   writeFunc mOutput $ LT.strip DS.forwarderDocumentation
      Analyze -> do
        let
          printItem :: (L.Text, AnalyzerRes) -> IO ()
          printItem (name, res) =
            putTextLn $ fmt $ nameF (build name) $ build res

        printItem ("DS Token Forwarder Contract", DS.analyzeForwarder)

