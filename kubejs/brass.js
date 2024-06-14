//ServerEvents.recipes(event => {
//    event.shapeless(Item.of('4x #forge:ingots/brass'), ['#forge:ingots/copper', '#forge:ingots/copper', '#forge:ingots/copper', '#forge:ingots/zinc'])
//  })
ServerEvents.recipes(event => {
    event.shaped("4x #forge:ingots/brass", [
      "CCC", 
      "Z  ", 
      "   "
    ], {
      C: "#forge:ingots/copper",
      Z: "#forge:ingots/zinc",
    });
  })