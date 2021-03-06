#' @title calcExcretion
#' @description calculates excretion during grazing, cropland-grazing, confinement and collected for fuel. Based on MAgPIE Feed baskets, slaughter biomass and simple allocation rules. 
#'
#' @param cellular if TRUE value is calculate and returned (set aggregate to FALSE!) on cellular level
#' @param attributes npk (default) or npkc (inclusing carbon) can be selected
#'
#' @return List of magpie object with results on country level, weight on country level, unit and description.
#' @author Benjamin Leon Bodirsky
#' @seealso
#' \code{\link{calcExcretionIPCC}}
#' @examples
#' 
#' \dontrun{ 
#' calcOutput("Excretion")
#' }
#' @importFrom magclass getNames<-

calcExcretion<-function(cellular=FALSE, attributes="npk"){
  
  #read in sets
  nutrients  <- c("nr","p","k")
  past       <- findset("past")
  kres       <- findset("kres")
  kli2       <- findset(set = "kli", alias=TRUE)
  kli        <- findset(set = "kli")
  
  #read in inputs
  
  CroplandGrazingShare       <- collapseNames(1-calcOutput("DevelopmentState", aggregate = F)[,past,"SSP2"])*0.25
  FuelShare                  <- collapseNames(calcOutput("ManureFuelShr", aggregate = F)[,past,"SSP2"])
  getNames(FuelShare, dim=1) <- paste0("alias_", getNames(FuelShare, dim=1))
  
    
  Feed          <- calcOutput("FeedPast", balanceflow=TRUE, aggregate = FALSE,nutrients=nutrients)[,past,][,,kli2]
  
  #calculate feeding categories
  LeftOnPasture            <- collapseNames(Feed[,,"pasture"] * (1-FuelShare))
  RemovedForFuel           <- collapseNames(Feed[,,"pasture"] * (FuelShare))
  LeftOnCropland           <- dimSums(Feed[,,kres] * CroplandGrazingShare, dim=3.2)
  FeedTotal                <- dimSums(Feed,dim=3.2)

  
  Confinement              <- FeedTotal  - LeftOnPasture  - RemovedForFuel - LeftOnCropland
  
  FeedingSystems      <- mbind( add_dimension(LeftOnPasture,  dim = 3.1, nm = "grazing"),
                                add_dimension(RemovedForFuel, dim = 3.1, nm = "fuel"),
                                add_dimension(LeftOnCropland, dim = 3.1, nm = "stubble_grazing"),
                                add_dimension(Confinement,    dim = 3.1, nm = "confinement"))
  
  
  SlaughterFeedShare                 <- collapseNames(calcOutput("SlaughterFeedShare", aggregate = FALSE, balanceflow = TRUE)[,past,nutrients][,,"constant"][,,kli])
  getNames(SlaughterFeedShare,dim=1) <- paste0("alias_",getNames(SlaughterFeedShare, dim = 1))
 
  Excretion                          <- FeedingSystems  *  ( 1 - SlaughterFeedShare )
  
  Excretion[is.na(Excretion)]        <- 0
  getNames(Excretion, dim=2)         <- substring(getNames(Excretion, dim=2),7)

  
  if(cellular){
    LivestockProduction <- collapseNames(calcOutput("LivestockGridded", details=TRUE, aggregate=FALSE)[,,"dm"])
  
    ProductionWeights   <- new.magpie(getItems(LivestockProduction, dim=1), 
                                      getItems(LivestockProduction, dim=2), 
                                      outer(getNames(Excretion, dim=1),getNames(Excretion, dim=2), paste, sep="."),
                                      fill = 0)
    
    ProductionWeights[,,"grazing"][,,c("livst_rum","livst_milk")]          <- LivestockProduction[,,"ext"][,,c("livst_rum","livst_milk")]
    ProductionWeights[,,"fuel"][,,c("livst_rum","livst_milk")]             <- LivestockProduction[,,"ext"][,,c("livst_rum","livst_milk")]
    ProductionWeights[,,"stubble_grazing"][,,c("livst_rum","livst_milk")]  <- LivestockProduction[,,"int"][,,c("livst_rum","livst_milk")]
    ProductionWeights[,,"confinement"][,,c("livst_rum","livst_milk")]      <- LivestockProduction[,,"int"][,,c("livst_rum","livst_milk")]
    ProductionWeights[,,c("livst_chick","livst_egg","livst_pig")]          <- dimSums(LivestockProduction[,,c("livst_chick","livst_egg","livst_pig")], dim=3.1)
    
    
    
    mapping <- toolMappingFile(type="cell",name = "CountryToCellMapping.csv",readcsv = TRUE)
    mapping <- mapping[which(mapping$iso%in%getRegions(LivestockProduction)),]
    Excretion<-toolAggregate(Excretion[getRegions(LivestockProduction),,], rel = mapping, weight = ProductionWeights, from = "iso", to="celliso", dim=1)
  }
  Excretion                          <- round(Excretion,8)
  
  if(attributes=="npkc"){
    CNratio            <- collapseNames(readSource("IPCC", subtype="manure_table5p5c", convert=FALSE)[,,"cn_ratio"])
    Excretion          <- add_columns(Excretion, addnm="c", dim=3.3)
    Excretion[,,"c"]   <- Excretion[,,"nr"]*CNratio
  }
  
  return(list(x=Excretion,
              weight=NULL,
              unit="Mt Nr, P, K (, C)",
              min=0,
              description="Excreted nutrients per animal type and animal waste system",
              isocountries=!cellular)
  )                   
}

