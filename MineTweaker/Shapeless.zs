###############################################################
##															 ##
##	    			Shapeless.zs						     ##
##				by Daniel Clark 05/04/2018					 ##
##															 ##
##															 ##
###############################################################






### Sample Code##################################################################################################################################


#//Item Pieces into Chunks and Back
#recipes.addShapeless(<exnihiloadscensio:itemOreLead> * 4, [<exnihiloadscensio:itemOreLead:1>]);
#recipes.addShapeless(<exnihiloadscensio:itemOreIron> * 4, [<exnihiloadscensio:itemOreIron:1>]);
#recipes.addShapeless(<exnihiloadscensio:itemOreGold> * 4, [<exnihiloadscensio:itemOreGold:1>]);
#recipes.addShapeless(<exnihiloadscensio:itemOreAluminium> * 4, [<exnihiloadscensio:itemOreAluminium:1>]);
#recipes.addShapeless(<exnihiloadscensio:itemOreCopper> * 4, [<exnihiloadscensio:itemOreCopper:1>]);
#recipes.addShapeless(<exnihiloadscensio:itemOreArdite> * 4, [<exnihiloadscensio:itemOreArdite:1>]);
#recipes.addShapeless(<exnihiloadscensio:itemOreCobalt> * 4, [<exnihiloadscensio:itemOreCobalt:1>]);
#recipes.addShapeless(<exnihiloadscensio:itemOreSilver> * 4, [<exnihiloadscensio:itemOreSilver:1>]);
#recipes.addShapeless(<exnihiloadscensio:itemOreNickel> * 4, [<exnihiloadscensio:itemOreNickel:1>]);

#<tp:QuartzKnife>.maxDamage = 100;

#//Refined Storage Changes
#recipes.addShapeless(<refinedstorage:grid:1>, [<refinedstorage:grid>, <minecraft:crafting_table>, <refinedstorage:processor:5>]);
#recipes.addShapeless(<refinedstorage:grid:2>, [<refinedstorage:grid>, <refinedstorage:pattern>, <refinedstorage:processor:5>]);
#recipes.addShapeless(<refinedstorage:grid:3>, [<refinedstorage:grid>, <minecraft:bucket>, <refinedstorage:processor:5>]);
################################################################################################################################################



#charcoal to coal
recipes.addShapeless(<minecraft:coal>, [<ore:charcoal>]);
