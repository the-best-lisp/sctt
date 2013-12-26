{-#LANGUAGE NamedFieldPuns, RecordWildCards, GeneralizedNewtypeDeriving, GADTs, ScopedTypeVariables #-}
module TypeCheck where
import Terms
import qualified Data.Map as M

import Control.Monad.Reader
import Control.Applicative
import Eq
import Fresh
import Ident
{-type H = Int

data Result a = Success | Cont [(H,a)] | Fail String

newtype TC a = TC {fromTC :: H -> Result a}

instance Monad TC where
  return x = TC (\h -> Cont [(H,a)])
  TC f >>= g = TC $ \h0 -> case f h0 of
    Success -> Success
    Fail s  -> Fail s
    Cont xs -> [ fromTC g a h1 | (h1,a) <- xs] 
-}  

  
-- Infer the type of a destruction and return it as a normal form.
inferDestr :: (n~Id,r~Id) => Destr r -> (Conc r ->  M n r Bool) -> M n r Bool
inferDestr (Cut v vt) k = do
  checkConcl v vt
  k vt
inferDestr (App f a_) k =
  inferHyp f $ \ft -> 
  case ft of
    (Pi x t_ u) -> do
       checkConcl a_ t_
       retTyp <- M $ lift $ subst x a_ u
       onConcl retTyp k
inferDestr (Proj p f) k =
  inferHyp p $ \pt ->
  case pt of
    (Sigma x t_ u) -> do
       case f of
         First -> k t_
         Second -> do
           x' <- M $ lift $ freshId
           u' <- substM x x' u
           onConcl (Destr x' (Proj p First) u' ) k

-- Direct lookup of type in the context
inferHyp :: (n~Id,r~Id) => Hyp r -> (Constr n r -> M n r Bool) -> M n r Bool
inferHyp h k = do
  ctx <- context <$> ask
  case M.lookup h ctx of
    Just c -> do
      lookHeapC c k

addCtx' :: Ord n => n -> Conc r -> Heap n r -> Heap n r
addCtx' x t h@Heap{..} = h{context = M.insert x t context }

addCtx x t k = local (addCtx' x t) k


-- maintains the invariant that every hyp. has an entry in the context.
checkBindings :: (n ~ r, Ord r) => Term n r -> (Conc r -> M n r Bool) -> M n r Bool
checkBindings (Conc c) k = k c
checkBindings (Constr x c t1) k = addConstr x c (checkBindings t1 k) -- FIXME: check lambdas?!
checkBindings (Destr x d t1) k =
  inferDestr d $ \dt ->
  addCtx x dt (addDestr x d $ checkBindings t1 k)
checkBindings (Case x bs) k =
  inferHyp x $ \xt -> 
  case xt of
    Fin ts -> do
      rs <- forM bs $ \(Br tag t1) -> do
        when (tag `notElem` ts) $ error "type error in case"
        addConstr x (Tag tag) $ checkBindings t1 k
      return $ and rs

checkTermAgainstTerm :: Term n r -> Term n r -> M n r Bool
checkTermAgainstTerm e t = checkBindings e $ \c -> checkConAgainstTerm c t

checkConAgainstTerm :: Conc r -> Term n r -> M n r Bool
checkConAgainstTerm c t = onConcl t $ \t' -> checkConcl c t'

checkConcl :: Conc r -> r -> M n r Bool
checkConcl v t = lookHeapC t $ \t' -> checkConclAgainstConstr v t'

checkConclAgainstConstr :: Conc r -> Constr n r -> M n r Bool
checkConclAgainstConstr v t = lookHeapC v $ \v' -> checkConstr v' t

checkConstr :: Constr n r -> Constr n r -> M n r Bool
checkConstr (Pair a_ b_) (Sigma xx ta_ tb_) = do
  checkConcl a_ ta_
  checkConAgainstTerm b_ =<< substM xx a_ tb_

checkConstr (Lam x b_) (Pi xx ta_ tb_) = do
  local (addCtx xx ta_) $ checkConAgainstTerm b_ tb_

checkConstr (Tag t) (Fin ts) = return (t `elem` ts)

checkConstr (Sigma xx ta_ tb_) (Universe s) =
  checkConclAgainstConstr ta_ (Universe s)
  local (addCtx xx ta_) $ checkConstr tb_ (Universe s)

checkConstr (Pi xx ta_ tb_) (Universe s) =
  checkConclAgainstConstr ta_ (Universe s)
  local (addCtx xx ta_) $ checkConstr tb_ (Universe s)

checkConstr (Fin _) (Universe _) = return True

checkConstr _ _ = error "tc. error"


