{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE OverloadedLabels #-}

{-# OPTIONS -Wall -Wno-unused-do-bind -Wno-orphans #-}

module Lorentz.Contracts.Forwarder.DS.V1 where

import Lorentz.Base (analyzeLorentz)
import Michelson.Text
import Michelson.Typed.T
import Lorentz
import qualified Lorentz.Contracts.Upgradeable.Common as Upgradeable
-- import Michelson.Typed.Haskell.Instr.Sum
-- import Michelson.Typed.Haskell.Value
import Michelson.Typed.Value
import Michelson.Typed.Instr (Instr)
import Michelson.Analyzer (AnalyzerRes)

import qualified Lorentz.Contracts.DS.V1 as DS
import qualified Lorentz.Contracts.DS.V1.Registry.Types as Registry
import qualified Lorentz.Contracts.DS.V1.Token.Types as Token

import GHC.TypeLits (KnownSymbol, Symbol)
import Prelude (Show(..), Enum(..), ($), id)

import Data.Vinyl.Derived (Label)


instance IsoValue (Value' Instr a) where
  type ToT (Value' Instr a) = a
  toVal = id
  fromVal = id

deriving instance (Show a, Show r) => Show (View a r)
deriving instance Show a => Show (ContractAddr a)
deriving instance Show (Upgradeable.Parameter entries)

-- | Construct a 'UParam' safely. See `mkUParam`.
toUParam
  :: forall name (a :: *) (entries :: [EntryPointKind]) s.
     ( KnownSymbol name, IsoValue a, KnownValue a, NoOperation a, NoBigMap a
     , LookupEntryPoint name entries ~ a
     , RequireUniqueEntryPoints entries
     )
  => Label name -> (a & s) :-> (UParam entries & s)
toUParam label = do
  pack
  push $ labelToMText label
  pair
  coerce_

-- | The number of sub-tokens to forward
type Parameter = Natural

-- | We need the addresses of:
-- - The sub-token contract, assumed to accept `DS.Parameter`
-- - The central wallet to transfer sub-tokens to
data Storage = Storage
  { subTokenContract :: ContractAddr DS.Parameter
  , centralWallet :: Address
  }
  deriving stock Eq
  deriving stock Show
  deriving stock Generic
  deriving anyclass IsoValue

-- | `coerce_`
toWalletId :: (Address & s) :-> (Registry.WalletId & s)
toWalletId = coerce_

-- | Convert to `Address` and amount to `Token.ParameterTransfer`
toTokenTransfer :: (Address & Natural & s) :-> (Token.ParameterTransfer & s)
toTokenTransfer = do
  pair
  coerce_
  dip $ do
    push $ Token.CommitRun
  pair
  wrap_ @Token.ParameterTransfer #cTransfer

-- | Would like to use `wrap_`, but couldn't get it to work for `Upgradeable.Parameter`
--
-- If it worked with `wrap_`, it'd be:
--
-- @
--  `wrap_` \@(`UParam` entries) #cRun
-- @
toParameterRun :: forall entries s. (UParam entries & s) :-> (Upgradeable.Parameter entries & s)
toParameterRun = do
  coerce_ @(UParam entries) @(Value ('TPair ('Tc 'CString) ('Tc 'CBytes)))
  left @(Value ('TPair ('Tc 'CString) ('Tc 'CBytes))) @(Value ('TPair ('Tc 'CNat) ('TPair ('TLambda ('TBigMap 'CBytes ('Tc 'CBytes)) ('TBigMap 'CBytes ('Tc 'CBytes))) ('TLambda ('TPair ('TPair ('Tc 'CString) ('Tc 'CBytes)) ('TBigMap 'CBytes ('Tc 'CBytes))) ('TPair ('TList 'TOperation) ('TBigMap 'CBytes ('Tc 'CBytes)))))))
  left @_ @(Value ('TOr ('TPair 'TUnit ('TContract ('Tc 'CNat))) ('Tc 'CAddress)))
  left @_ @(Value ('TOr ('TOr ('Tc 'CNat) ('TLambda ('TBigMap 'CBytes ('Tc 'CBytes)) ('TBigMap 'CBytes ('Tc 'CBytes)))) ('TOr ('TLambda ('TPair ('TPair ('Tc 'CString) ('Tc 'CBytes)) ('TBigMap 'CBytes ('Tc 'CBytes))) ('TPair ('TList 'TOperation) ('TBigMap 'CBytes ('Tc 'CBytes)))) 'TUnit)))
  coerce_

-- | Convert to `Address` and amount to `DS.Parameter`
toTransferParameter :: (Address & Natural & s) :-> (DS.Parameter & s)
toTransferParameter = do
  toTokenTransfer
  toUParam #callTokenTransfer
  toParameterRun

-- | Run a transfer, given the amount and the `Storage`,
-- containing the central wallet address and sub token
-- contract address.
runTransfer :: (Natural & Storage & s) :-> (Operation & Storage & s)
runTransfer = do
  dip $ do
    getField #centralWallet
  swap
  toTransferParameter
  dip $ do
    getField #subTokenContract
    push (toEnum 0 :: Mutez)
  transferTokens

-- | Forwarder contract: forwards the given number of sub-tokens
-- from its own address to the central wallet.
forwarderContract :: Contract Parameter Storage
forwarderContract = do
  unpair
  runTransfer
  dip nil
  cons
  pair

forwarderCompilationWay :: LorentzCompilationWay Parameter Storage
forwarderCompilationWay = lcwDumb

-- forwarderDocumentation :: LText

analyzeForwarder :: AnalyzerRes
analyzeForwarder = analyzeLorentz forwarderContract
