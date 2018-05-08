##################################################################
##                                                              ##
##         Created by Daniel Clark   01/31/2018                 ##
##                                                              ##
##################################################################

print("Initializing 'ddc.zs'...");

recipes.addShaped(<minecraft:blaze_rod>*1, [[<minecraft:blaze_powder>,<minecraft:blaze_powder>, null],[null,null,null],[null,null,null]]);

recipes.addShaped(<bigreactors:ingotmetals:3>*1, [[<bigreactors:ingotmetals:1>, <bigreactors:ingotmetals:1>, null],[null,null,null],[null,null,null]]);

recipes.addShaped(<actuallyadditions:itemDust:7>*12, [[<environmentaltech:hardened_stone>, <environmentaltech:hardened_stone>, <environmentaltech:hardened_stone>],[<environmentaltech:hardened_stone>, <minecraft:dye:4>, <environmentaltech:hardened_stone>],[<environmentaltech:hardened_stone>, <environmentaltech:hardened_stone>, <environmentaltech:hardened_stone>,]]);

recipes.addShaped(<thermalfoundation:material:164>*2, [[<thermalfoundation:material:133>, <thermalfoundation:material:128>, null], [null, null, null],[null, null, null]]);

print("All Done");