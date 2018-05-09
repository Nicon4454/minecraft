###############################################################
##							     ##
##	          Shapeless.zs                               ##
##	    by Daniel Clark 05/04/2018                       ##
##                                                           ##
##                                                           ##
###############################################################


### Sample Code #######################



#recipes.addShapeless(<exnihiloadscensio:itemOreNickel> * 4, [<exnihiloadscensio:itemOreNickel:1>]);

#<tp:QuartzKnife>.maxDamage = 100;

#//Refined Storage Changes
#recipes.addShapeless(<refinedstorage:grid:1>, [<refinedstorage:grid>, <minecraft:crafting_table>, <refinedstorage:processor:5>]);
#recipes.addShapeless(<refinedstorage:grid:2>, [<refinedstorage:grid>, <refinedstorage:pattern>, <refinedstorage:processor:5>]);
#recipes.addShapeless(<refinedstorage:grid:3>, [<refinedstorage:grid>, <minecraft:bucket>, <refinedstorage:processor:5>]);
########################################



#charcoal to coal
recipes.addShapeless(<minecraft:coal>, [<ore:charcoal>]);
