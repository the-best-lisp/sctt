{-#LANGUAGE NamedFieldPuns, RecordWildCards, GeneralizedNewtypeDeriving, GADTs, ScopedTypeVariables, OverloadedStrings, TypeSynonymInstances, FlexibleInstances, FlexibleContexts, MultiParamTypeClasses #-}
module TCM where

import Terms
import Ident
import Fresh
import Display
import Control.Monad.Reader
import Control.Monad.Writer
import Control.Monad.RWS
import Control.Monad.Error
import Control.Applicative
import Data.Map (Map)

type Term' = Term Id Id
type Constr' = Constr Id Id
type Destr' = Destr Id
type Heap' = Heap Id Id
type Branch' = Branch Id Id


type DeCo r = Either (Destr r) (Conc r)

data Heap n r = Heap { heapConstr :: Map (Conc n) (Constr n r)
                     , heapCuts   :: Map (Hyp n) (DeCo r)  -- TODO: rename to heapDestr
                     , heapDestr  :: Map (Destr r) (Hyp n) -- TODO: rename to heapDestr'
                     , heapTags   :: Map r String
                     , heapAlias  :: Map r r
                     , context    :: Map n (Conc r) -- ^ types
                     }

instance (Pretty r, Pretty n) => Pretty (Heap n r) where
  pretty (Heap {..}) = sep [hang lab 2  v
                           | (lab,v) <- [("constr" ,pretty heapConstr)
                                        ,("cuts"   ,pretty heapCuts)
                                        ,("destr"  ,pretty heapDestr)
                                        ,("tags"   ,pretty heapTags)
                                        ,("alias"  ,pretty heapAlias)
                                        ,("context",pretty context)]
                             ]

newtype TC a = TC {fromTC :: ErrorT Doc (RWST Heap' [Doc] () FreshM) a}
  deriving (Functor, Applicative, Monad, MonadReader Heap', MonadWriter [Doc], MonadError Doc)

instance Error Doc where
  noMsg = "unknown error"
  strMsg = text

runTC :: Unique -> Heap' -> TC a -> (Either Doc a,[Doc])
runTC u h0 (TC x) = runFreshMFromUnique u $ evalRWST (runErrorT x) h0 ()

liftTC :: FreshM a -> TC a
liftTC x = TC $ lift $ lift x

substTC xx a_ bb = liftTC (subst xx a_ bb)

terr :: Doc -> TC a
terr msg = do
  h <- ask
  throwError $ sep [hang "heap" 2 (pretty h), msg]
