{-# Language PatternSynonyms, CApiFFI, ViewPatterns #-}
module LibBF.Opts where

import Data.Word
import Foreign.C.Types
import Data.Bits
import Data.List
#include <libbf.h>

type LimbT = #{type limb_t}
type FlagsT = #{type bf_flags_t}

data BFOpts = BFOpts !LimbT !FlagsT

instance Semigroup BFOpts where
  BFOpts l f <> BFOpts l1 f1 = BFOpts (max l l1) (f .|. f1)


-- | Use infinite precision.
infPrec :: BFOpts
infPrec = BFOpts #{const BF_PREC_INF} 0

-- | Use this many bits to represent the mantissa in the computation.
-- The input should be in the interval defined by "precMin" and "precMax"
precBits :: Int -> BFOpts
precBits n = BFOpts (fromIntegral n) 0

rnd :: RoundMode -> BFOpts
rnd (RoundMode r) = BFOpts 0 r


-- | The smallest supported precision.
foreign import capi "libbf.h value BF_PREC_MIN"
  precMin :: Int

-- | The largest supported precision.
foreign import capi "libbf.h value BF_PREC_MAX"
  precMax :: Int

{- | Allow denormalized answers. -}
allowSubnormal :: BFOpts
allowSubnormal = BFOpts 0 #{const BF_FLAG_SUBNORMAL}


foreign import capi "libbf.h bf_set_exp_bits"
  bf_set_exp_bits :: CInt -> FlagsT

-- | Set how many bits to use to represent the exponent.
-- Should fit in the range defined by "expBitsMin" "expBitsMax"
expBits :: Int -> BFOpts
expBits n = BFOpts 0 (bf_set_exp_bits (fromIntegral n))

{-| The smallest supported number of bits in the exponent. -}
foreign import capi "libbf.h value BF_EXP_BITS_MIN"
  expBitsMin :: Int

{-| The largest number of exponent bits supported. -}
foreign import capi "libbf.h value BF_EXP_BITS_MAX"
  expBitsMax :: Int


--------------------------------------------------------------------------------

float64 :: RoundMode -> BFOpts
float64 r = rnd r <> precBits 53 <> expBits 11



--------------------------------------------------------------------------------

data ShowFmt = ShowFmt !LimbT !FlagsT

-- | Use this rounding mode.
showRnd :: RoundMode -> ShowFmt
showRnd (RoundMode r) = ShowFmt 1 r

instance Semigroup ShowFmt where
  ShowFmt a x <> ShowFmt b y = ShowFmt (max a b) (x .|. y)

{-| Show this many significant digits after the decimal point. -}
showFixed :: Word64 -> ShowFmt
showFixed n = ShowFmt n #{const BF_FTOA_FORMAT_FIXED}

{-| Show this many digits after the floating point. -}
showFrac :: Word64 -> ShowFmt
showFrac n = ShowFmt n #{const BF_FTOA_FORMAT_FRAC}

{-| Use as many digits as necessary to match the required precision
   rounding to nearest and the subnormal+exponent configuration of 'flags'.
   The result is meaningful only if the input is already rounded to
   the wanted precision.

   Infinite precision, indicated by giving 'Nothing' for the precision
   is supported when the radix is a power of two. -}
showFree :: Maybe Word64 -> ShowFmt
showFree mb = ShowFmt prec #{const BF_FTOA_FORMAT_FREE}
  where prec = case mb of
                 Nothing -> #{const BF_PREC_INF}
                 Just n  -> n


{-| same as 'showFree' but uses the minimum number of digits
(takes more computation time). -}
showFreeMin :: Maybe Word64 -> ShowFmt
showFreeMin mb = ShowFmt prec #{const BF_FTOA_FORMAT_FREE_MIN}
  where prec = case mb of
                 Nothing -> #{const BF_PREC_INF}
                 Just n  -> n



{- | add 0x prefix for base 16, 0o prefix for base 8 or 0b prefix for
   base 2 if non zero value -}
addPrefix :: ShowFmt
addPrefix = ShowFmt 0 #{const BF_FTOA_ADD_PREFIX}

forceExp :: ShowFmt
forceExp = ShowFmt 0 #{const BF_FTOA_FORCE_EXP}





--------------------------------------------------------------------------------
newtype RoundMode = RoundMode FlagsT

{-| Round to nearest, ties go to even. -}
pattern NearEven :: RoundMode
pattern NearEven = RoundMode #{const BF_RNDN}

{-| Round to nearest, ties go away from zero. -}
pattern NearAway :: RoundMode
pattern NearAway = RoundMode #{const BF_RNDNA}

{-| Round to nearest, ties go up (toward +inf) -}
pattern NearUp :: RoundMode
pattern NearUp = RoundMode #{const BF_RNDNU}

{-| Round down (toward -inf). -}
pattern ToNegInf :: RoundMode
pattern ToNegInf = RoundMode #{const BF_RNDD}

{-| Round up (toward +inf). -}
pattern ToPosInf :: RoundMode
pattern ToPosInf = RoundMode #{const BF_RNDU}

{-| Round toward zero. -}
pattern ToZero :: RoundMode
pattern ToZero = RoundMode #{const BF_RNDZ}

{-| Faithful rounding (nondeterministic, either "ToPosInf" or "ToNegInf").
    The "Inexact" flag is always set. -}
pattern Faithful :: RoundMode
pattern Faithful = RoundMode #{const BF_RNDF}


--------------------------------------------------------------------------------

-- | A set of flags indicating things that might go wrong.
newtype Status = Status CInt deriving (Eq,Ord)

checkStatus :: CInt -> Status -> Bool
checkStatus n (Status x) = (x .&. n) > 0

-- | Everything went as expected.
pattern Ok :: Status
pattern Ok = Status 0

-- | We tried to perform an invalid operation.
pattern InvalidOp :: Status
pattern InvalidOp <- (checkStatus #{const BF_ST_INVALID_OP} -> True)
  where InvalidOp = Status #{const BF_ST_INVALID_OP}

-- | We divided by zero.
pattern DivideByZero :: Status
pattern DivideByZero <- (checkStatus #{const BF_ST_DIVIDE_ZERO} -> True)
  where DivideByZero = Status #{const BF_ST_DIVIDE_ZERO}

-- | The result can't be represented because it is too large.
pattern Overflow :: Status
pattern Overflow <- (checkStatus #{const BF_ST_OVERFLOW} -> True)
  where Overflow = Status #{const BF_ST_OVERFLOW}

-- | The result can't be represented because it is too small.
pattern Underflow :: Status
pattern Underflow <- (checkStatus #{const BF_ST_UNDERFLOW} -> True)
  where Underflow = Status #{const BF_ST_UNDERFLOW}

-- | The result is not exact.
pattern Inexact :: Status
pattern Inexact <- (checkStatus #{const BF_ST_INEXACT} -> True)
  where Inexact = Status #{const BF_ST_INEXACT}

instance Show Status where
  show x@(Status i) = case x of
                        Ok -> "Ok"
                        _  -> case checkInv of
                                [] -> "(Status " ++ show i ++ ")"
                                xs -> "[" ++ intercalate "," xs ++ "]"
    where
    checkInv = case x of
                 InvalidOp -> "InvalidOp" : checkZ
                 _         -> checkZ

    checkZ = case x of
               DivideByZero -> "DivideByZero" : checkO
               _            -> checkO

    checkO = case x of
               Overflow -> "Overflow" : checkU
               _        -> checkU

    checkU = case x of
               Underflow -> "Underflow" : checkI
               _ -> checkI

    checkI = case x of
               Inexact -> ["Inexact"]
               _       -> []

