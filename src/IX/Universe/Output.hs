module IX.Universe.Output
   (updateAMap
   ,updatePmap
   ,updateAgents
   ,lookToAgt
   ,cErrToAgt
   ) where

import DataStructures.Atomic
import DataStructures.Composite
import IX.Universe.Utils (setMessage,mkAgent,getPlanet)
import IX.Universe.HyperSpace (getName,setRepairField)

import qualified Data.Map as M
import Data.Maybe (mapMaybe)
import Data.Text (unpack)
import Data.List (foldl')
import Data.List.Utils (addToAL)
import Safe (fromJustNote)


updateAMap :: DAgentMap -> AgentMap -> AgentMap
updateAMap (DAgentMap (SubAgentMap agts)) (AgentMap aMap) =
  AgentMap $ M.foldlWithKey updateAgents aMap agts

--updateAMap (DAgentMap (SubAgentMap [])) aMap' = aMap'

updateAMap (LocationUpdate messages) (AgentMap aMap) =
  AgentMap $ M.foldlWithKey updateMessages aMap messages

updateAMap ClearOut (AgentMap aMap) =
  AgentMap $ M.map (repairShip . markDead . removeMSG) aMap

updateAgents :: M.Map AID Agent -> AID -> Agent -> M.Map AID Agent
updateAgents aMap aid agt = M.insert aid agt aMap

updateMessages :: M.Map AID Agent -> AID -> Message -> M.Map AID Agent
updateMessages aMap aid msg =
  let agt = setMessage [msg] $ fromJustNote upMessageFail (M.lookup aid aMap)
  in M.insert aid agt aMap 
  where
    upMessageFail =
      "updateMessage failed to find " ++
      show aid                        ++
      "in agent map\n"

removeMSG :: Agent -> Agent
removeMSG agt =
  case agt of
    (Dead _) -> agt
    _        -> setMessage [] agt

markDead :: Agent -> Agent
markDead agt =
  case agt of
     (Dead _) -> agt -- no more game messages
     _        ->
        case isDead agt of
          True  -> Dead name
              where
                name = getName agt
          False -> agt


repairShip :: Agent -> Agent
repairShip agt@(Player {ship = Ship shipParts shipStats}) =
  case repairing shipStats of
    True
       | hullStrength < maxStrength -> repairShip'
       | otherwise                  -> stopRepairing
    False                           -> agt
  where
     (HullStrength hullStrength) = hull_strength shipStats
     maxStrength       = PInt $ (fromEnum $ hull shipParts) * 100
     repairShip'       =
        agt {ship = Ship shipParts setHealthField}
     setHealthField    =
        shipStats {hull_strength = HullStrength $ hullStrength + (PInt 20)}
     stopRepairing     = setRepairField False agt

repairShip agt = agt

updatePmap :: LocationMap -> AgentMap -> PlanetMap -> PlanetMap
updatePmap (LocationMap l_map) (AgentMap a_map) (PlanetMap p_map) =
   -- add recently landed
  let landed   = M.foldlWithKey addLanded p_map l_map
   -- bring out yer dead
      deadGone = M.foldlWithKey (removeDead a_map) landed $ findPlanetSide l_map
   -- then remove the ones that just left. 
  in PlanetMap $ M.foldlWithKey removeDeparted deadGone l_map

lookToAgt :: AgentMap -> (AID,Result) -> Maybe DAgentMap
lookToAgt (AgentMap aMap) (aid@(AID aid'),Looked res ship) =
   let o_agent = fromJustNote aAgentFail (M.lookup aid aMap)
   in case res of
         Left pName ->
            Just $ DAgentMap $ mkAgent (aid,o_agent) (PlanetLoc pName)
         Right hyp  ->
            Just $ DAgentMap $ mkAgent (aid,o_agent) (InHyp hyp)
   where
      aAgentFail = "lookToAgt failed to match aid " ++ unpack aid'

lookToAgt _ _ = Nothing

cErrToAgt :: AgentMap -> (AID,Result) -> Maybe DAgentMap
cErrToAgt (AgentMap aMap') (aid, (CError cerr)) =
   let oAgent  = fromJustNote cErrToAgtERR (M.lookup aid aMap')
       naAgent = setMessage [CommandErr cerr] oAgent
   in Just $ DAgentMap $ SubAgentMap $ M.singleton aid naAgent
    where
      cErrToAgtERR = "cErrToAgt failed to find "       ++
                     "the following agent in AgentMap" ++
                     (show aid)
cErrToAgt _ _ = Nothing

addLanded :: M.Map PlanetName Planet    ->
             AID                        ->
             Location                   ->
             M.Map PlanetName Planet
addLanded p_map aid (Location (Left (pName,Landed))) =
  case (isAdded aid planet) of
    True  -> p_map
    False -> M.insert pName addResident p_map  
   where
     addResident = setResidents uResidents $ planet
     uResidents  = (residents planet) ++ [aid]
     planet      = getPlanet pName (PlanetMap p_map)

addLanded pMap _ _  = pMap

removeDeparted :: M.Map PlanetName Planet ->
                  AID                     ->
                  Location                ->
                  M.Map PlanetName Planet
removeDeparted pMap aid (Location (Right (hyp,Launched))) =
  let planet' = removeResident aid planet
  in M.insert pName planet' pMap
  where
    (FromPlanetName pName) = origin hyp
    planet = getPlanet pName (PlanetMap pMap)

removeDeparted pMap _ _ = pMap

removeDead :: M.Map AID Agent         ->
              M.Map PlanetName Planet ->
              AID                     ->
              PlanetName              ->
              M.Map PlanetName Planet
removeDead aMap pMap aid pName =
   let agent = fromJustNote aAgentFail (M.lookup aid aMap)
   in case agent of
      (Dead _) -> let planet =
                         removeResident aid $
                         fromJustNote planetFail (M.lookup pName pMap)
                  in M.insert pName planet pMap
                  where
                     planetFail = "removeDead failed to find this " ++
                                  "planet from PlanetMap "          ++
                                  (show pName)                      ++
                                    "\n"
      _        -> pMap
   where
      aAgentFail = "removeDead failed to find this agent in AgentMap" ++
                   (show aid)                                         ++
                   "\n"


findPlanetSide :: M.Map AID Location -> M.Map AID PlanetName
findPlanetSide locs =
   M.mapMaybe findPlanetSide' locs
   where
     findPlanetSide' :: Location -> Maybe PlanetName
     findPlanetSide' (Location (Left (pName,_))) = Just pName
     findPlanetSide' _                           = Nothing

isAdded :: AID -> Planet -> Bool
isAdded aid (Planet {residents = aids}) = aid `elem` aids

--unwrap :: PlanetNameWrapper -> PlanetName
--unwrap (FP_W (FromPlanetName fpn)) = fpn
--unwrap (TP_W (ToPlanetName tpn))   = tpn
-----getters setters -----
setResidents :: [AID] -> Planet -> Planet
setResidents aids planet = planet { residents = aids }

removeResident :: AID -> Planet -> Planet
removeResident aid planet@(Planet {residents = aids}) =
   flip setResidents planet $ filter (/= aid) aids

