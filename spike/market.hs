import System.Random
import Data.Ord 
import Data.Eq
import Debug.Trace

data PriceRoll = Increment
               | Decrement

res1 = Resource {
   highestPrice = PInt 5000
  ,lowestPrice  = PInt 1000
  ,currentPrice = PInt 2500
  ,stability    = Volatile
}

res2 = Resource {
   highestPrice = PInt 500
  ,lowestPrice  = PInt 100
  ,currentPrice = PInt 250
  ,stability    = Volatile
}

res3 = Resource {
   highestPrice = PInt 10000
  ,lowestPrice  = PInt 5000
  ,currentPrice = PInt 7500
  ,stability    = Volatile
}

data ResourceMap = ResourceMap ![(ResourceName,Resource)] deriving Show
data ResourceName = FinestGreen
                  | SubstanceD
                  | BabyBlue
                  | Melange
                  | InterzoneSpecial
                     deriving (Ord,Eq,Show,Read,Enum,Bounded)

data Resource = Resource {
   highestPrice :: PInt
  ,lowestPrice  :: PInt
  ,currentPrice :: PInt
  ,stability    :: Stability
} deriving (Show,Ord,Eq)

data PInt = PInt Int

fromPInt :: PInt -> Int
fromPInt (PInt a) = a

toPInt :: Int -> PInt
toPInt = PInt

instance Num PInt where

   x - y = x `truncSub` y
           where
              truncSub (PInt x) (PInt y)
                 | y > x     = PInt 0
                 | otherwise = PInt $ x - y

   x + y = PInt $ (fromPInt x) + (fromPInt y)

   x * y = PInt $ (fromPInt x) * (fromPInt y)

   abs x = x

   signum x = 1

   fromInteger x = PInt $ fromInteger x 

instance Eq PInt where
   x == y = fromPInt x == fromPInt y
   x /= y = fromPInt x /= fromPInt y

instance Ord PInt where
   x <= y = fromPInt x <= fromPInt y
   x < y         = fromPInt x < fromPInt y
   x > y         = fromPInt x > fromPInt y

instance Show PInt where
   show x = show $ fromPInt x

data Stability = Volatile
               | Stable PInt
                  deriving (Show,Eq,Ord)

adjustMarket :: [Integer] -> ResourceMap -> ResourceMap
adjustMarket dRolls (ResourceMap rMap) =
   let currentRolls = take (length rMap) dRolls
       matchedRolls = zip rMap currentRolls
   in ResourceMap $ map adjustLocalMarket matchedRolls

adjustLocalMarket :: ((ResourceName,Resource),Integer) -> 
                     (ResourceName,Resource)
adjustLocalMarket ((rName,res),roll) =
   case (stability res) of
      Stable cDown -> (manageStability cDown) 
      Volatile     -> (rName,priceADJ)
   where
      manageStability (PInt cDown) 
         | cDown == 0 = (rName,endStability)
         | otherwise  = (rName,decStability)
         where
            endStability = res {stability = Volatile}
            decStability = res {stability = Stable $ PInt (cDown - 1)}
      priceADJ
         | (roll <= 50) = stableOrDec
         | otherwise    = stableOrInc
         where
            stableOrDec
               | (cPrice > lPrice) = stability_check Decrement
               | otherwise         = res
             
            stableOrInc 
               | (cPrice < hPrice) = stability_check Increment
               | otherwise         = res
            stability_check Decrement
               | (roll <= 20) = stablize $ dec_price
               | otherwise    = dec_price
            stability_check Increment
               | (roll >= 80) = stablize $ inc_price
               | otherwise    = inc_price
            
            stablize res' = res' {stability = Stable $ PInt 500}            
            cPrice        = currentPrice res
            lPrice        = lowestPrice res
            hPrice        = highestPrice res
            dec_price     = res {currentPrice = cPrice - pDec}
            inc_price     = res {currentPrice = cPrice + pDec}
            pDec          = PInt 1
 
