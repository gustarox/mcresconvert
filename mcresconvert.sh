#!/bin/bash

# enable this to see which line cause warnings
# set -o xtrace

ZENITY="zenity --width 800 --title mcresconvert"

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
	echo "Usage: $(basename $0) [OPTIONS]"
	echo "   [OPTIONS] can be:"
	echo "   - <file>    - a zip filename to convert"
	echo "   - all       - attempts to convert all installed resource packs"
	echo "   - default   - attempts to convert the default resource pack"
	exit 1
fi

for required in unzip convert composite; do
	type $required > /dev/null
	if [ $? -ne 0 ]; then
		echo "Unable to find \"$required\" program, exiting"
		exit 1
	fi
done

type zenity > /dev/null
if [ $? -ne 0 ]; then
	echo "WARNING: Zenity not found, attempting to continue without gui support"
	NOGUI=yes
fi

convert_alphatex() {
	if [ -f _n/$2 ]; then
		g="_n/$2"
		if [ -f "$g.mcmeta" ]; then
			if grep -q "animation" "$g.mcmeta"; then
				# FIXME: need a list of not animated textures
				if echo "$5" | grep -q "grass"; then
					w=`file $g |sed 's/.*, \([0-9]*\) x \([0-9]*\).*/\1/'`
					convert "$g" -crop ${w}x${w}+0+0 -depth 8 _n/_g.png
					g="_n/_g.png"
				fi
			fi
		fi
		convert $1 -crop 1x1+$3 -depth 8 -resize ${4}x${4} _n/_c.png
		composite -compose Multiply _n/_c.png $g _n/_i.png
		composite -compose Dst_In $g _n/_i.png -alpha Set $5
		echo -e "." >> _n/_tot
		echo -e "." >> _n/_counter
	fi
}

copy_or_crop_from_anim() {
	IN=$1
	OUT=$2

	crop="0"
	if [ -f "$IN.mcmeta" ]; then
		if grep -q "animation" "$IN.mcmeta"; then
			# items are never animated in minetest
			if echo $IN | grep -q "/items/"; then
				crop="1"
			fi
			# in minetest blocks textures are called *_animated.png" if they are
			if ! echo $OUT | grep -q "_animated.png"; then
				crop="1"
			fi
		fi
	fi

	if [ "$crop" == "1" ]; then
		convert "$IN" -crop ${PXSIZE}x${PXSIZE}+0+0 -depth 8 "$OUT"
	else
		cp "$IN" "$OUT"
	fi
}

compose_door() {
	l=$1
	u=$2
	r=$3

	if [ -f $l -a -f $u ]; then
		# Cut out first frame if animated texture
		if [ -f $l.mcmeta ]; then
			w=`file $l |sed 's/.*, \([0-9]*\) x.*/\1/'`
			convert $l -background none -crop ${w}x${w}+0+0 _n/_cl.png
			l=_n/_cl.png
		fi
		if [ -f $u.mcmeta ]; then
			w=`file $u |sed 's/.*, \([0-9]*\) x.*/\1/'`
			convert $u -background none -crop ${w}x${w}+0+0 _n/_cu.png
			u=_n/_cu.png
		fi
		convert -background none $u -resize ${PXSIZE}x${PXSIZE} _n/_u.png
		convert -background none $l -resize ${PXSIZE}x${PXSIZE} _n/_l.png
		convert -background none _n/_u.png -flop _n/_fu.png
		convert -background none _n/_l.png -flop _n/_fl.png
		montage -background none _n/_fu.png _n/_u.png _n/_fl.png _n/_l.png -geometry +0+0 _n/_d.png
		convert _n/_d.png -background none -extent $(( (PXSIZE * 2) + (3 * (PXSIZE / 8) ) ))x$((PXSIZE * 2)) _n/_d2.png
		convert _n/_d2.png \
			\( -clone 0 -crop $((PXSIZE/8))x$((PXSIZE*2))+$((PXSIZE-1))+0 \) -gravity NorthWest -geometry +$((PXSIZE*2))+0 -composite \
			\( -clone 0 -crop $((PXSIZE/16))x$((PXSIZE*2))+0+0 \) -gravity NorthWest -geometry +$((PXSIZE*2+(PXSIZE/8)))+0 -composite \
			\( -clone 0 -crop $((PXSIZE/16))x$((PXSIZE*2))+$((PXSIZE*2-1))+0 \) -gravity NorthWest -geometry +$((PXSIZE*2+(3*(PXSIZE/16))))+0 -composite \
			\( -clone 0 -crop $((PXSIZE/16))x$((PXSIZE*2))+0+0 \) -gravity NorthWest -geometry +$((PXSIZE*2+(4*(PXSIZE/16))))+0 -composite \
			\( -clone 0 -crop $((PXSIZE/16))x$((PXSIZE*2))+$((PXSIZE*2-1))+0 \) -gravity NorthWest -geometry +$((PXSIZE*2+(5*(PXSIZE/16))))+0 -composite \
			$r
		return 0
	fi
	return 1
}

make_fence() {
	def=$1
	plank=$2
	out=$3
	if [ ! -f $def -a -f $plank ]; then
		w=`file $plank |sed 's/.*, \([0-9]*\) x.*/\1/'`
		if [ $w -eq $((PXSIZE/4)) ]; then
			convert $plank \( -clone 0 -rotate 90 -gravity center \) -composite $out
		else
			convert $plank \( -clone 0 -crop $((PXSIZE))x$((PXSIZE/4))+0+$(((PXSIZE/8)*3)) -rotate 90 -gravity center \) -composite $out
		fi
	elif [ -f $def ]; then
		cp $def $out
	fi
}

make_grass() {
	i=$1
	cmap=$2
	def=$3
	out=$4
	seg=$5
	if [ -f $i ]; then
		convert_alphatex $cmap $i 70+120 ${PXSIZE} $out
	else
		convert $def -page +0+$(((PXSIZE/8) * seg)) -background none -flatten $out
	fi
}

convert_file() {
	n=`basename "$@" .zip | tr -d ' \t."()[]' | tr -d "'"`
	echo "Found: $n"
	echo "   - File: `basename "$@"`"
	(
		texture_dir=~/.minetest/textures
		if [ ! -d $texture_dir ]; then
		  if [ -n "$NOGUI" ]; then
				echo "Creating texture directory under: \"$texture_dir\"."
			else
				$ZENITY --info --text="Creating texture directory under: \"$texture_dir\"." 2> /dev/null ;
			fi
			mkdir -p $texture_dir
		fi
		if ! mkdir $texture_dir/$n > /dev/null 2>&1 ; then
			if [ -n "$NOGUI" ]; then
				echo "A texture pack with name \"$n\" already exists, remove it before trying again."
				exit 1
			else
				if ! $ZENITY --question --text="A texture pack folder with name \"$n\" already exists, overwrite?" --default-cancel 2> /dev/null ; then
					exit 1
				fi
			fi
			rm -rf $texture_dir/$n
			mkdir $texture_dir/$n
		fi
		mkdir $texture_dir/$n/_z
		unzip -qq "$@" -d $texture_dir/$n/_z || exit 1
		cd $texture_dir/$n/_z
		# what a bunch of nonsense
		chmod -R +w *
		rm -rf __MACOSX
		assets_dir=`find * -name 'assets' -type 'd'`
		if [ -z "$assets_dir" ]; then
			echo "No 'assets' found in $@"
			exit 1
		fi
		if [ ! -d "$assets_dir"/minecraft/textures ]; then
			echo "No directory \"$assets_dir/minecraft/textures\" found in $@"
			exit 1
		fi
		# beware of zip files with a random extra toplevel folder.
		ln -sf _z/"$assets_dir"/minecraft/textures ../_n || exit 1
		cd ..

		# try and determine px size
		if [ -f "_n/blocks/cobblestone.png" ]; then
			PXSIZE=`file _n/blocks/cobblestone.png |sed 's/.*, \([0-9]*\) x.*/\1/'`
		fi

		( cat <<RENAMES
items/apple.png default_apple.png
items/bed.png beds_bed.png
blocks/bed_feet_end.png beds_bed_side_bottom.png
blocks/bed_feet_side.png beds_bed_side_bottom_r.png
blocks/bed_feet_side.png beds_bed_side_bottom_l.png h
blocks/bed_feet_top.png beds_bed_top_bottom.png
blocks/bed_head_end.png beds_bed_side_top.png
blocks/bed_head_top.png beds_bed_top_top.png
blocks/bed_head_side.png beds_bed_side_top_r.png
blocks/bed_head_side.png beds_bed_side_top_l.png h
items/boat.png boats_inventory.png
items/book_writable.png default_book.png
items/book_written.png default_book_written.png
blocks/bookshelf.png default_bookshelf.png
items/bread.png farming_bread.png
items/bucket_empty.png bucket.png
items/bucket_lava.png bucket_lava.png
items/bucket_water.png bucket_water.png
items/bucket_water.png bucket_river_water.png
items/brick.png default_clay_brick.png
blocks/brick.png default_brick.png
items/clay_ball.png default_clay_lump.png
blocks/clay.png default_clay.png
items/coal.png default_coal_lump.png
blocks/coal_block.png default_coal_block.png
blocks/coal_ore.png mcl_core_coal_ore.png
blocks/cobblestone.png default_cobble.png
blocks/cobblestone_mossy.png default_mossycobble.png
blocks/deadbush.png default_dry_shrub.png
items/diamond.png default_diamond.png
items/diamond_axe.png default_tool_diamondaxe.png
blocks/diamond_block.png default_diamond_block.png
items/diamond_hoe.png farming_tool_diamondhoe.png
blocks/diamond_ore.png mcl_core_diamond_ore.png
items/diamond_pickaxe.png default_tool_diamondpick.png
items/diamond_shovel.png default_tool_diamondshovel.png
items/diamond_sword.png default_tool_diamondsword.png

items/gold_axe.png default_tool_goldaxe.png
blocks/gold_block.png default_gold_block.png
items/gold_hoe.png farming_tool_goldhoe.png
blocks/gold_ore.png mcl_core_gold_ore.png
items/gold_pickaxe.png default_tool_goldpick.png
items/gold_shovel.png default_tool_goldshovel.png
items/gold_sword.png default_tool_goldsword.png

blocks/dirt.png default_dirt.png
blocks/coarse_dirt.png mcl_core_coarse_dirt.png

items/door_wood.png doors_item_wood.png
items/door_iron.png doors_item_steel.png
items/dye_powder_black.png dye_black.png
items/dye_powder_blue.png dye_blue.png
items/dye_powder_brown.png dye_brown.png
items/dye_powder_cyan.png dye_cyan.png
items/dye_powder_green.png dye_dark_green.png
items/dye_powder_lime.png dye_green.png
items/dye_powder_gray.png dye_dark_grey.png
items/dye_powder_magenta.png dye_magenta.png
items/dye_powder_orange.png dye_orange.png
items/dye_powder_pink.png dye_pink.png
items/dye_powder_purple.png dye_violet.png
items/dye_powder_red.png dye_red.png
items/dye_powder_silver.png dye_grey.png
items/dye_powder_white.png dye_white.png
items/dye_powder_yellow.png dye_yellow.png
blocks/farmland_dry.png farming_soil.png
blocks/farmland_wet.png farming_soil_wet.png
blocks/fire_layer_0.png fire_basic_flame_animated.png
items/flint.png default_flint.png

blocks/flower_allium.png  mcl_flowers_allium.png
blocks/flower_blue_orchid.png  mcl_flowers_blue_orchid.png
blocks/flower_dandelion.png  flowers_dandelion_yellow.png
blocks/flower_houstonia.png  mcl_flowers_houstonia.png
blocks/flower_oxeye_daisy.png  mcl_flowers_oxeye_daisy.png
blocks/flower_paeonia.png  mcl_flowers_paeonia.png
blocks/flower_pot.png  mcl_flowers_pot.png
blocks/flower_rose.png  flowers_rose.png
blocks/flower_rose.png  mcl_flowers_poppy.png
blocks/flower_tulip_orange.png  flowers_tulip.png
blocks/flower_tulip_pink.png  mcl_flowers_tulip_pink.png
blocks/flower_tulip_red.png  mcl_flowers_tulip_red.png
blocks/flower_tulip_white.png  mcl_flowers_tulip_white.png
blocks/fern.png mcl_flowers_fern.png
blocks/double_plant_rose_bottom.png mcl_flowers_double_plant_rose_bottom.png
blocks/double_plant_rose_top.png mcl_flowers_double_plant_rose_top.png
blocks/double_plant_grass_bottom.png mcl_flowers_double_plant_grass_bottom.png
blocks/double_plant_grass_top.png mcl_flowers_double_plant_grass_top.png

items/melon.png farming_melon.png
blocks/melon_side.png farming_melon_side.png 
blocks/melon_top.png farming_melon_top.png

blocks/furnace_front_off.png default_furnace_front.png
blocks/furnace_front_on.png default_furnace_front_active.png
blocks/furnace_side.png default_furnace_side.png
blocks/furnace_top.png default_furnace_bottom.png
blocks/furnace_top.png default_furnace_top.png
blocks/glass.png default_glass.png
blocks/glass_gray.png default_obsidian_glass.png
blocks/gold_block.png default_gold_block.png
items/gold_ingot.png default_gold_ingot.png
items/gold_nugget.png default_gold_lump.png
blocks/gold_ore.png mcl_core_gold_ore.png
blocks/grass_side.png default_grass_side.png
blocks/grass_side_snowed.png mcl_core_grass_side_snowed.png
blocks/grass_path_side.png mcl_core_grass_path_side.png
blocks/grass_path_top.png mcl_core_grass_path_top.png

blocks/gravel.png default_gravel.png
blocks/hay_block_side.png mcl_farming_hayblock_side.png
blocks/hay_block_top.png mcl_farming_hayblock_top.png
blocks/jukebox_side.png mcl_jukebox_side.png
blocks/jukebox_top.png mcl_jukebox_top.png  

blocks/ice.png default_ice.png
blocks/iron_bars.png xpanes_bar.png
items/iron_axe.png default_tool_steelaxe.png
items/iron_hoe.png farming_tool_steelhoe.png
items/iron_pickaxe.png default_tool_steelpick.png
items/iron_shovel.png default_tool_steelshovel.png
items/iron_sword.png default_tool_steelsword.png
blocks/iron_block.png default_steel_block.png
items/iron_ingot.png default_steel_ingot.png
blocks/iron_ore.png mcl_core_iron_ore.png
blocks/iron_trapdoor.png doors_trapdoor_steel.png
blocks/iron_trapdoor.png doors_trapdoor_steel_side.png
blocks/ladder.png default_ladder.png
blocks/lava_flow.png default_lava_flowing_animated.png
blocks/lava_still.png default_lava_source_animated.png
blocks/log_oak.png default_tree.png
blocks/log_oak_top.png default_tree_top.png
blocks/log_acacia.png default_acacia_tree.png
blocks/log_acacia_top.png default_acacia_tree_top.png
blocks/log_big_oak.png mcl_core_log_big_oak.png
blocks/log_big_oak_top.png mcl_core_log_big_oak_top.png
blocks/planks_big_oak.png mcl_core_planks_big_oak.png

blocks/bedrock.png mcl_core_bedrock.png
blocks/log_birch.png mcl_core_log_birch.png
blocks/log_birch_top.png mcl_core_log_birch_top.png
blocks/log_jungle.png default_jungletree.png
blocks/log_jungle_top.png default_jungletree_top.png
blocks/log_spruce.png mcl_core_log_spruce.png
blocks/log_spruce_top.png mcl_core_log_spruce_top.png
blocks/mushroom_brown.png flowers_mushroom_brown.png
blocks/mushroom_red.png flowers_mushroom_red.png
blocks/obsidian.png default_obsidian.png
items/paper.png default_paper.png
blocks/planks_acacia.png default_acacia_wood.png
blocks/planks_birch.png mcl_core_planks_birch.png
blocks/planks_jungle.png default_junglewood.png
blocks/planks_oak.png default_wood.png
blocks/planks_spruce.png mcl_core_planks_spruce.png
blocks/rail_normal.png default_rail.png
blocks/rail_normal_turned.png default_rail_curved.png
blocks/red_sand.png mcl_core_red_sand.png
blocks/red_sandstone_normal.png mcl_core_red_sandstone.png
blocks/red_sandstone_smooth.png mcl_core_red_sandstone_smooth.png
blocks/red_sandstone_carved.png mcl_core_red_sandstone_carvedk.png
blocks/red_sandstone_top.png mcl_core_red_sandstone_top.png
blocks/reeds.png mcl_core_reeds.png
blocks/sand.png default_sand.png
blocks/sandstone_top.png mcl_core_sandstone.png
blocks/sandstone_normal.png mcl_core_sandstone_normal.png
blocks/sandstone_carved.png mcl_core_sandstone_carved.png
blocks/sandstone_top.png mcl_core_sandstone_top.png

blocks/sapling_birch.png default_aspen_sapling.png
blocks/sapling_jungle.png default_junglesapling.png
blocks/sapling_spruce.png default_pine_sapling.png
blocks/sapling_oak.png default_sapling.png
blocks/sapling_acacia.png default_acacia_sapling.png
items/seeds_wheat.png farming_wheat_seed.png
items/sign.png default_sign_wood.png
items/sign.png default_sign_wall_wood.png
items/snowball.png default_snowball.png
blocks/snow.png default_snow.png
items/stick.png default_stick.png
items/string.png farming_cotton.png
items/stone_axe.png default_tool_stoneaxe.png
items/stone_hoe.png farming_tool_stonehoe.png
items/stone_pickaxe.png default_tool_stonepick.png
items/stone_shovel.png default_tool_stoneshovel.png
items/stone_sword.png default_tool_stonesword.png
blocks/stone.png default_stone.png
blocks/stonebrick.png default_stone_brick.png
blocks/stonebrick_carved.png default_stone_block.png
items/sugar.png farming_flour.png
blocks/tnt_bottom.png default_tnt_bottom.png
blocks/tnt_side.png default_tnt_side.png
blocks/tnt_top.png default_tnt_top.png
blocks/tnt_top.png default_tnt_top_burning.png
blocks/tnt_top.png default_tnt_top_burning_animated.png
blocks/torch_on.png default_torch_animated.png
blocks/torch_on.png default_torch_on_floor_animated.png
blocks/trapdoor.png doors_trapdoor.png
blocks/trapdoor.png doors_trapdoor_side.png
blocks/water_still.png default_water_source_animated.png
blocks/water_still.png default_river_water_source_animated.png
blocks/water_flow.png default_water_flowing_animated.png
blocks/water_flow.png default_river_water_flowing_animated.png
items/wheat.png farming_wheat.png
blocks/wheat_stage_0.png farming_wheat_1.png
blocks/wheat_stage_1.png farming_wheat_2.png
blocks/wheat_stage_2.png farming_wheat_3.png
blocks/wheat_stage_3.png farming_wheat_4.png
blocks/wheat_stage_4.png farming_wheat_5.png
blocks/wheat_stage_5.png farming_wheat_6.png
blocks/wheat_stage_6.png farming_wheat_7.png
blocks/wheat_stage_7.png farming_wheat_8.png
items/wood_axe.png default_tool_woodaxe.png
items/wood_hoe.png farming_tool_woodhoe.png
items/wood_pickaxe.png default_tool_woodpick.png
items/wood_shovel.png default_tool_woodshovel.png
items/wood_sword.png default_tool_woodsword.png
blocks/wool_colored_black.png wool_black.png
blocks/wool_colored_blue.png wool_blue.png
blocks/wool_colored_brown.png wool_brown.png
blocks/wool_colored_cyan.png wool_cyan.png
blocks/wool_colored_gray.png wool_dark_grey.png
blocks/wool_colored_green.png wool_dark_green.png
blocks/wool_colored_lime.png wool_green.png
blocks/wool_colored_magenta.png wool_magenta.png
blocks/wool_colored_orange.png wool_orange.png
blocks/wool_colored_pink.png wool_pink.png
blocks/wool_colored_purple.png wool_violet.png
blocks/wool_colored_red.png wool_red.png
blocks/wool_colored_silver.png wool_grey.png
blocks/wool_colored_white.png wool_white.png
blocks/wool_colored_yellow.png wool_yellow.png
blocks/redstone_lamp_on.png default_meselamp.png
blocks/redstone_ore.png mcl_core_redstone_ore.png
blocks/pumpkin_top.png farming_pumpkin_top.png
blocks/pumpkin_side.png farming_pumpkin_side.png
blocks/pumpkin_face_on.png farming_pumpkin_face_light.png
blocks/pumpkin_face_off.png farming_pumpkin_face.png
blocks/crafting_table_front.png crafting_workbench_front.png
blocks/crafting_table_side.png crafting_workbench_side.png
blocks/crafting_table_top.png crafting_workbench_top.png

blocks/hardened_clay.png hardened_clay.png
blocks/hardened_clay_stained_black.png hardened_clay_stained_black.png
blocks/hardened_clay_stained_blue.png hardened_clay_stained_blue.png
blocks/hardened_clay_stained_brown.png hardened_clay_stained_brown.png
blocks/hardened_clay_stained_cyan.png hardened_clay_stained_cyan.png
blocks/hardened_clay_stained_gray.png hardened_clay_stained_gray.png
blocks/hardened_clay_stained_green.png hardened_clay_stained_green.png
blocks/hardened_clay_stained_light_blue.png hardened_clay_stained_light_blue.png
blocks/hardened_clay_stained_lime.png hardened_clay_stained_lime.png
blocks/hardened_clay_stained_magenta.png hardened_clay_stained_magenta.png
blocks/hardened_clay_stained_orange.png hardened_clay_stained_orange.png
blocks/hardened_clay_stained_pink.png hardened_clay_stained_pink.png
blocks/hardened_clay_stained_purple.png hardened_clay_stained_purple.png
blocks/hardened_clay_stained_red.png hardened_clay_stained_red.png
blocks/hardened_clay_stained_silver.png hardened_clay_stained_silver.png
blocks/hardened_clay_stained_white.png hardened_clay_stained_white.png
blocks/hardened_clay_stained_yellow.png hardened_clay_stained_yellow.png

blocks/lapis_ore.png mcl_core_lapis_ore.png
items/dye_powder_blue.png default_lapis.png
blocks/stone_granite.png mcl_core_granite.png
blocks/stone_andesite.png mcl_core_andesite.png
blocks/stone_diorite.png mcl_core_diorite.png
blocks/stone_slab_side.png mcl_stairs_stone_slab_side.png
blocks/stone_slab_top.png mcl_stairs_stone_slab_top.png

blocks/mushroom_red.png farming_mushroom_red.png
blocks/mushroom_red.png flowers_mushroom_red.png
blocks/mushroom_red.png mobs_mc_mushroom_red.png
blocks/mushroom_brown.png farming_mushroom_brown.png
blocks/mushroom_brown.png flowers_mushroom_brown.png
blocks/mushroom_brown.png mobs_mc_mushroom_brown.png

entity/creeper/creeper.png mobs_mc_creeper.png
entity/creeper/creeper_armor.png mobs_mc_creeper_armor.png 
entity/cat/ocelot.png mobs_mc_cat_ocelot.png
entity/cat/black.png mobs_mc_cat_black.png
entity/cat/red.png mobs_mc_cat_red.png
entity/cat/siamese.png mobs_mc_cat_siamese.png
entity/cow/cow.png mobs_mc_cow.png
entity/cow/mooshroom.png mobs_mc_mooshroom.png
entity/zombie/zombie.png mobs_mc_zombie.png
entity/skeleton/skeleton.png mobs_mc_skeleton.png
entity/skeleton/wither_skeleton.png mobs_mc_wither_skeleton.png 
entity/enderman/enderman.png mobs_mc_enderman.png
entity/enderman/enderman_eyes.png mobs_mc_enderman_eyes.png
entity/spider/spider.png mobs_mc_spider.png 
entity/spider/cave_spider.png mobs_mc_cave_spider.png
entity/slime/slime.png mobs_mc_slime.png
entity/sheep/sheep.png mobs_mc_sheep.png
entity/sheep/sheep_fur.png mobs_mc_sheep_fur.png

blocks/dropper_front_horizontal.png mcl_droppers_dropper_front_horizontal.png
blocks/dropper_front_vertical.png mcl_droppers_dropper_front_vertical.png
blocks/emerald_ore.png mcl_core_emerald_ore.png
blocks/emerald_block.png mcl_core_emerald_block.png

blocks/glass_black.png  mcl_core_glass_black.png
blocks/glass_blue.png  mcl_core_glass_blue.png
blocks/glass_brown.png  mcl_core_glass_brown.png
blocks/glass_cyan.png  mcl_core_glass_cyan.png
blocks/glass_gray.png  mcl_core_glass_gray.png
blocks/glass_green.png  mcl_core_glass_green.png
blocks/glass_light_blue.png  mcl_core_glass_light_blue.png
blocks/glass_lime.png  mcl_core_glass_lime.png
blocks/glass_magenta.png  mcl_core_glass_magenta.png
blocks/glass_orange.png  mcl_core_glass_orange.png
blocks/glass_pane_top_black.png  mcl_core_glass_pane_top_black.png
blocks/glass_pane_top_blue.png  mcl_core_glass_pane_top_blue.png
blocks/glass_pane_top_brown.png  mcl_core_glass_pane_top_brown.png
blocks/glass_pane_top_cyan.png  mcl_core_glass_pane_top_cyan.png
blocks/glass_pane_top_gray.png  mcl_core_glass_pane_top_gray.png
blocks/glass_pane_top_green.png  mcl_core_glass_pane_top_green.png
blocks/glass_pane_top_light_blue.png  mcl_core_glass_pane_top_light_blue.png
blocks/glass_pane_top_lime.png  mcl_core_glass_pane_top_lime.png
blocks/glass_pane_top_magenta.png  mcl_core_glass_pane_top_magenta.png
blocks/glass_pane_top_orange.png  mcl_core_glass_pane_top_orange.png
blocks/glass_pane_top_pink.png  mcl_core_glass_pane_top_pink.png
blocks/glass_pane_top.png  mcl_core_glass_pane_top.png
blocks/glass_pane_top_purple.png  mcl_core_glass_pane_top_purple.png
blocks/glass_pane_top_red.png  mcl_core_glass_pane_top_red.png
blocks/glass_pane_top_silver.png  mcl_core_glass_pane_top_silver.png
blocks/glass_pane_top_white.png  mcl_core_glass_pane_top_white.png
blocks/glass_pane_top_yellow.png  mcl_core_glass_pane_top_yellow.png
blocks/glass_pink.png  mcl_core_glass_pink.png
blocks/glass.png  mcl_core_glass.png
blocks/glass_purple.png  mcl_core_glass_purple.png
blocks/glass_red.png  mcl_core_glass_red.png
blocks/glass_silver.png  mcl_core_glass_silver.png
blocks/glass_white.png  mcl_core_glass_white.png
blocks/glass_yellow.png  mcl_core_glass_yellow.png

blocks/rail_activator.png mcl_minecarts_rail_activator.png
blocks/rail_activator_powered.png mcl_minecarts_rail_activator_powered.png
blocks/rail_detector.png mcl_minecarts_rail_detector.png
blocks/rail_detector_powered.png mcl_minecarts_rail_detector_powered.png
blocks/rail_golden.png mcl_minecarts_rail_golden.png
blocks/rail_golden_powered.png mcl_minecarts_rail_golden_powered.png
blocks/rail_normal.png mcl_minecarts_rail_normal.png
blocks/rail_normal_turned.png mcl_minecarts_rail_normal_turned.png

items/door_acacia.png  mcl_doors_door_acacia.png 
items/door_dark_oak.png mcl_doors_door_dark_oak.png
items/door_birch.png mcl_doors_door_birch.png
items/door_iron.png mcl_doors_door_iron.png
items/door_jungle.png  mcl_doors_door_jungle.png 
items/door_spruce.png mcl_doors_door_spruce.png
items/door_wood.png  mcl_doors_door_wood.png 

items/fish_clownfish_raw.png mcl_fishing_clownfish_raw.png
items/fish_cod_cooked.png mcl_fishing_fish_cod_cooked.png
items/fish_cod_raw.png mcl_fishing_fish_cod_raw.png
items/fishing_rod_cast.png mcl_fishing_fishing_rod_cast.png
items/fish_pufferfish_raw.png mcl_fishing_fish_pufferfish_raw.png
items/fish_salmon_cooked.png mcl_fishing_fish_salmon_cooked.png
items/fish_salmon_raw.png mcl_fishing_fish_salmon_raw.png


RENAMES
) |		while read IN OUT FLAG; do
			echo -e "." >> _n/_tot
			if [ -f "_n/$IN" ]; then
				echo -e "." >> _n/_counter
				copy_or_crop_from_anim "_n/$IN" "$OUT"
			elif [ -f "_z/$IN" ]; then
				echo -e "." >> _n/_counter
				copy_or_crop_from_anim "_z/$IN" "$OUT"
			# uncomment below 2 lines to see if any textures were not found.
			else
				echo "+$IN $OUT $FLAG: Not Found"
			fi
		done

		# attempt to colorize grasses by color cradient
		echo -e ".." >> _n/_tot
		if [ -f "_n/colormap/grass.png" ]; then
			convert _n/colormap/grass.png -crop 1x1+70+120 -depth 8 -resize ${PXSIZE}x${PXSIZE} _n/_c.png
			composite -compose Multiply _n/_c.png _n/blocks/grass_top.png default_grass.png
			echo -e "." >> _n/_counter

			convert _n/colormap/grass.png -crop 1x1+16+240 -depth 8 -resize ${PXSIZE}x${PXSIZE} _n/_c.png
			composite -compose Multiply _n/_c.png _n/blocks/grass_top.png default_dry_grass.png
			echo -e "." >> _n/_counter

			convert_alphatex _n/colormap/grass.png blocks/tallgrass.png 70+120 ${PXSIZE} mcl_flowers_tallgrass.png
			make_grass blocks/tallgrass1.png _n/colormap/grass.png mcl_flowers_tallgrass.png default_grass_4.png 1
			make_grass blocks/tallgrass2.png _n/colormap/grass.png mcl_flowers_tallgrass.png default_grass_3.png 2
			make_grass blocks/tallgrass3.png _n/colormap/grass.png mcl_flowers_tallgrass.png default_grass_2.png 3
			make_grass blocks/tallgrass4.png _n/colormap/grass.png mcl_flowers_tallgrass.png default_grass_1.png 4
			#FIXME tile this
			convert_alphatex _n/colormap/grass.png blocks/grass_side_overlay.png 70+120 ${PXSIZE} default_grass_side.png

			convert_alphatex _n/colormap/grass.png blocks/tallgrass.png 16+240 ${PXSIZE} default_dry_grass_5.png
			make_grass blocks/tallgrass1.png _n/colormap/grass.png default_dry_grass_5.png default_dry_grass_4.png 1
			make_grass blocks/tallgrass2.png _n/colormap/grass.png default_dry_grass_5.png default_dry_grass_3.png 2
			make_grass blocks/tallgrass3.png _n/colormap/grass.png default_dry_grass_5.png default_dry_grass_2.png 3
			make_grass blocks/tallgrass4.png _n/colormap/grass.png default_dry_grass_5.png default_dry_grass_1.png 4
			#FIXME tile this
			convert_alphatex _n/colormap/grass.png blocks/grass_side_overlay.png 16+240 ${PXSIZE} default_dry_grass_side.png

			# jungle grass - compose from tall grass 2 parts
			if [ -f _n/colormap/grass.png -a -f _n/blocks/double_plant_grass_bottom.png -a -f _n/blocks/double_plant_grass_top.png ]; then
				convert_alphatex _n/colormap/grass.png blocks/double_plant_grass_bottom.png 16+32 ${PXSIZE} _n/_jgb.png
				convert_alphatex _n/colormap/grass.png blocks/double_plant_grass_top.png 16+32 ${PXSIZE} _n/_jgt.png
				montage -tile 1x2 -geometry +0+0 -background none _n/_jgt.png _n/_jgb.png default_junglegrass.png
				convert default_junglegrass.png -background none -gravity South -extent $((PXSIZE*2))x$((PXSIZE*2)) default_junglegrass.png
			fi
		fi

		# crack
		echo -e "." >> _n/_tot
		if [ -f "_n/blocks/destroy_stage_0.png" ]; then
			c=( _n/blocks/destroy_stage_*.png )
			montage -tile 1x${#c[@]} -geometry +0+0 -background none ${c[@]} _n/c.png
			convert _n/c.png -alpha on -background none -channel A -evaluate Min 50% crack_anylength.png
			echo -e "." >> _n/_counter
		fi

		# same for leaf colors
		if [ -f "_n/colormap/foliag.png" ]; then
			FOLIAG=_n/colormap/foliag.png
		elif [ -f "_n/colormap/foliage.png" ]; then
			FOLIAG=_n/colormap/foliage.png
		fi
		echo -e "." >> _n/_tot
		if [ -n "$FOLIAG" ]; then
			convert_alphatex $FOLIAG blocks/leaves_oak.png 70+120 ${PXSIZE} default_leaves.png
			convert_alphatex $FOLIAG blocks/leaves_acacia.png 16+240 ${PXSIZE} default_acacia_leaves.png
			convert_alphatex $FOLIAG blocks/leaves_spruce.png 226+240 ${PXSIZE} default_pine_needles.png
			convert_alphatex $FOLIAG blocks/leaves_birch.png 70+120 ${PXSIZE} default_aspen_leaves.png
			convert_alphatex $FOLIAG blocks/leaves_jungle.png 16+32 ${PXSIZE} default_jungleleaves.png
			convert_alphatex $FOLIAG blocks/waterlily.png 16+32 ${PXSIZE} flowers_waterlily.png
			convert_alphatex $FOLIAG blocks/waterlily.png 16+32 ${PXSIZE} flowers_waterlily_bottom.png
			echo -e "." >> _n/_counter
		fi

		# compose doors texture maps
		# TODO: minetest also has doors_door_{glass,obsidian}.png
		# TODO: minecraft also has: acacia, birch, dark_oak, jungle, spruce
		echo -e "." >> _n/_tot
		if compose_door _n/blocks/door_wood_lower.png _n/blocks/door_wood_upper.png mcl_doors_wooden_door.png; then
			echo -e "." >> _n/_counter
		fi

		echo -e "." >> _n/_tot
		if compose_door _n/blocks/door_iron_lower.png _n/blocks/door_iron_upper.png doors_door_steel.png; then
			echo -e "." >> _n/_counter
		fi

		# fences - make alternative from planks
		# TODO: minecraft has: big_oak
		make_fence _n/blocks/fence_oak.png _n/blocks/planks_oak.png mcl_fences_fence_oak.png
		make_fence _n/blocks/fence_acacia.png _n/blocks/planks_acacia.png mcl_fences_fence_acacia.png
		make_fence _n/blocks/fence_spruce.png _n/blocks/planks_spruce.png mcl_fences_fence_spruce.png
		make_fence _n/blocks/fence_jungle.png _n/blocks/planks_jungle.png mcl_fences_fence_jungle.png
		make_fence _n/blocks/fence_birch.png _n/blocks/planks_birch.png mcl_fences_fence_aspen.png

		# doors - make alternative 
		# TODO
		convert -flop _n/blocks/door_wood_upper.png mcl_doors_door_wood_upper.png
		convert -flop _n/blocks/door_wood_lower.png mcl_doors_door_wood_lower.png
		convert mcl_doors_door_wood_upper.png -crop 16x16+15+10 mcl_doors_door_wood_side_upper.png
		convert mcl_doors_door_wood_lower.png -crop 16x16+15+10 mcl_doors_door_wood_side_lower.png

		convert -flop _n/blocks/door_acacia_upper.png mcl_doors_door_acacia_upper.png
		convert -flop _n/blocks/door_acacia_lower.png mcl_doors_door_acacia_lower.png
		convert mcl_doors_door_acacia_upper.png -crop 16x16+15+10 mcl_doors_door_acacia_side_upper.png
		convert mcl_doors_door_acacia_lower.png -crop 16x16+15+10 mcl_doors_door_acacia_side_lower.png

		convert -flop _n/blocks/door_spruce_upper.png mcl_doors_door_spruce_upper.png
		convert -flop _n/blocks/door_spruce_lower.png mcl_doors_door_spruce_lower.png
		convert mcl_doors_door_spruce_upper.png -crop 16x16+15+10 mcl_doors_door_spruce_side_upper.png
		convert mcl_doors_door_spruce_lower.png -crop 16x16+15+10 mcl_doors_door_spruce_side_lower.png

		convert -flop _n/blocks/door_birch_upper.png mcl_doors_door_birch_upper.png
		convert -flop _n/blocks/door_birch_lower.png mcl_doors_door_birch_lower.png
		convert mcl_doors_door_birch_upper.png -crop 16x16+15+10 mcl_doors_door_birch_side_upper.png
		convert mcl_doors_door_birch_lower.png -crop 16x16+15+10 mcl_doors_door_birch_side_lower.png

		convert -flop _n/blocks/door_jungle_upper.png mcl_doors_door_jungle_upper.png
		convert -flop _n/blocks/door_jungle_lower.png mcl_doors_door_jungle_lower.png
		convert mcl_doors_door_jungle_upper.png -crop 16x16+15+10 mcl_doors_door_jungle_side_upper.png
		convert mcl_doors_door_jungle_lower.png -crop 16x16+15+10 mcl_doors_door_jungle_side_lower.png

		convert -flop _n/blocks/door_dark_oak_upper.png mcl_doors_door_dark_oak_upper.png
		convert -flop _n/blocks/door_dark_oak_lower.png mcl_doors_door_dark_oak_lower.png
		convert mcl_doors_door_dark_oak_upper.png -crop 16x16+15+10 mcl_doors_door_dark_oak_side_upper.png
		convert mcl_doors_door_dark_oak_lower.png -crop 16x16+15+10 mcl_doors_door_dark_oak_side_lower.png





		# chest textures
		echo -e "..." >> _n/_tot
		if [ -f _n/entity/chest/normal.png ]; then
			CHPX=$((PXSIZE / 16 * 14)) # chests in MC are 2/16 smaller!
			convert _n/entity/chest/normal.png \
				\( -clone 0 -crop $((CHPX))x$((CHPX))+$((CHPX))+0 \) -geometry +0+0 -composite -extent $((CHPX))x$((CHPX)) default_chest_top.png
			convert _n/entity/chest/normal.png \
				\( -clone 0 -crop $((CHPX))x$(((PXSIZE/16)*5))+$((CHPX))+$((CHPX)) \) -geometry +0+0 -composite \
				\( -clone 0 -crop $((CHPX))x$(((PXSIZE/16)*10))+$((CHPX))+$(( (2*CHPX)+((PXSIZE/16)*5) )) \) -geometry +0+$(((PXSIZE/16)*5)) -composite \
				-extent $((CHPX))x$((CHPX)) default_chest_front.png
			cp default_chest_front.png default_chest_lock.png
			convert _n/entity/chest/normal.png \
				\( -clone 0 -crop $((CHPX))x$(((PXSIZE/16)*5))+$((2*CHPX))+$((CHPX)) \) -geometry +0+0 -composite \
				\( -clone 0 -crop $((CHPX))x$(((PXSIZE/16)*10))+$((2*CHPX))+$(( (2*CHPX)+((PXSIZE/16)*5) )) \) -geometry +0+$(((PXSIZE/16)*5)) -composite \
				-extent $((CHPX))x$((CHPX)) mcl_chests_chest_right.png
			cp mcl_chests_chest_right.png mcl_chests_chest_left.png
			cp mcl_chests_chest_right.png mcl_chests_chest_back.png
			echo -e "..." >> _n/_counter
		fi

		echo -e "." >> _n/_tot
		if [ -f _n/environment/sun.png ]; then
			convert _n/environment/sun.png -colorspace HSB -separate _n/_mask.png
			convert _n/environment/sun.png -fill '#a1a1a1' -draw 'color 0,0 reset' _n/_lighten.png
			convert _n/_lighten.png _n/environment/sun.png -compose Lighten_Intensity -composite -alpha Off _n/_mask-2.png -compose CopyOpacity -composite PNG32:sun.png
			convert sun.png -bordercolor none -border 1x1 -fuzz 0% -trim sun.png
			rm _n/_mask*
			echo -e "." >> _n/_counter
		fi
		echo -e "." >> _n/_tot
		if [ -f _n/environment/moon_phases.png ]; then
			S=`identify -format "%[fx:w/4]" _n/environment/moon_phases.png`
			convert _n/environment/moon_phases.png -colorspace HSB -separate _n/_mask.png
			convert _n/environment/moon_phases.png -alpha Off _n/_mask-2.png -compose CopyOpacity -composite PNG32:moon.png
			convert -background none moon.png -gravity NorthWest -extent ${S}x${S} moon.png
			convert moon.png -bordercolor none -border 1x1 -fuzz 0% -trim moon.png
			echo -e "." >> _n/_counter
		fi

		# inventory torch
		echo -e "." >> _n/_tot
		if [ -f _n/blocks/torch_on.png ]; then
			convert _n/blocks/torch_on.png -background none -gravity North -extent ${PXSIZE}x${PXSIZE} default_torch_on_floor.png
			echo -e "." >> _n/_counter
		fi

		# hotbar
		echo -e "." >> _n/_tot
		if [ -f _n/gui/widgets.png ]; then
			convert _n/gui/widgets.png -resize 256x256 -background none -gravity NorthWest -crop 24x24+0+22 gui_hotbar_selected.png
			convert _n/gui/widgets.png -resize 256x256 -background none -gravity NorthWest -extent 140x22 _n/a.png
			convert _n/gui/widgets.png -resize 256x256 -background none -gravity NorthWest -crop 22x22+160+0 +repage -extent 22x22 _n/b.png
			montage _n/a.png _n/b.png -tile 2x1 -background none -geometry +0+0 PNG32:gui_hotbar.png
			echo -e "." >> _n/_counter
		fi

		# health & breath
		echo -e "." >> _n/_tot
		if [ -f _n/gui/icons.png ]; then
			convert _n/gui/icons.png -resize 256x256 -background none -gravity NorthWest -crop 9x9+52+0 heart.png
			convert _n/gui/icons.png -resize 256x256 -background none -gravity NorthWest -crop 9x9+16+18 bubble.png
			echo -e "." >> _n/_counter
		fi

		# steve? ha! This assumes 64x32 dimensions, won't work well with 1.8 skins.
		echo -e "." >> _n/_tot
		if [ -f _n/entity/steve.png ]; then
			S=`identify -format "%[fx:w]" _n/entity/steve.png`
			convert _n/entity/steve.png -background none -gravity NorthWest \
			-extent $((S))x$((S/2)) character.png
			echo -e "." >> _n/_counter
		fi

		# attempt to make desert cobblestone
		echo -e "." >> _n/_tot
		if [ -f _n/blocks/cobblestone.png -a -f _n/blocks/red_sand.png ]; then
			convert _n/blocks/red_sand.png -resize 1x1 -resize ${PXSIZE}x${PXSIZE} _n/_c.png
			convert _n/blocks/cobblestone.png _n/_c.png -compose Overlay -composite default_desert_cobble.png
			echo -e "." >> _n/_counter
		fi

		# make copper and bronze from colorizing steel
		echo -e "...." >> _n/_tot
		if [ -f _n/items/iron_ingot.png ]; then
			#ffa05b
			convert -size ${PXSIZE}x${PXSIZE} xc:\#CA8654 _n/_c.png

			composite -compose Screen _n/_c.png _n/items/iron_ingot.png _n/_i.png
			composite -compose Dst_In _n/items/iron_ingot.png _n/_i.png -alpha Set default_copper_ingot.png

			convert _n/blocks/iron_block.png _n/_c.png -compose Overlay -composite default_copper_block.png

			#ffb07c
			convert -size ${PXSIZE}x${PXSIZE} xc:\#6F4C35 _n/_c.png

			composite -compose Screen _n/_c.png _n/items/iron_ingot.png _n/_i.png
			composite -compose Dst_In _n/items/iron_ingot.png _n/_i.png -alpha Set default_bronze_ingot.png

			convert _n/blocks/iron_block.png _n/_c.png -compose Overlay -composite default_bronze_block.png
			echo -e "...." >> _n/_counter
		fi

		# de-animate flint and steel
		echo -e "." >> _n/_tot
		if [ -f _n/items/flint_and_steel.png ]; then
			convert -background none -gravity North -extent ${PXSIZE}x${PXSIZE} _n/items/flint_and_steel.png fire_flint_steel.png
			echo -e "." >> _n/_counter
		fi

		# cactus needs manual cropping
		echo -e ".." >> _n/_tot
		if [ -f _n/blocks/cactus_top.png ]; then
			convert _n/blocks/cactus_top.png -crop +$((PXSIZE/16))+$((PXSIZE/16))x$(((PXSIZE/16)*14))x$(((PXSIZE/16)*14)) +repage -extent $(((PXSIZE/16)*14))x$(((PXSIZE/16)*14)) mcl_core_cactus_top.png
			convert _n/blocks/cactus_side.png -crop +$((PXSIZE/16))+$((PXSIZE/16))x$(((PXSIZE/16)*14))x$(((PXSIZE/16)*14)) +repage -extent $(((PXSIZE/16)*14))x$(((PXSIZE/16)*14)) mcl_core_cactus_side.png
			echo -e ".." >> _n/_counter
		fi

		# steel ladder
		echo -e "." >> _n/_tot
		if [ -f _n/blocks/ladder.png ]; then
			convert _n/blocks/ladder.png -channel RGBA -matte -colorspace gray default_ladder_steel.png
			echo -e "." >> _n/_counter
		fi

		# steel sign
		echo -e ".." >> _n/_tot
		if [ -f _n/items/sign.png ]; then
			convert _n/items/sign.png -channel RGBA -matte -colorspace gray default_sign_steel.png
			convert _n/items/sign.png -channel RGBA -matte -colorspace gray default_sign_wall_steel.png
			echo -e ".." >> _n/_counter
		fi

		# emerald -> mese
		if [ -f _n/blocks/emerald_ore.png ]; then
			compare _n/blocks/stone.png _n/blocks/emerald_ore.png -metric AE -fuzz 5% -compose Src -highlight-color White -lowlight-color none _n/m.png 2> /dev/null
			composite -compose Dst_In -gravity center _n/m.png _n/blocks/emerald_ore.png -alpha Set _n/o.png
			convert _n/o.png -modulate 100,100,80 default_mineral_mese.png
			convert _n/blocks/emerald_block.png -modulate 100,100,80 mcl_core_emerald_block.png
			convert _n/items/emerald.png -modulate 100,100,80 default_mese_crystal.png
		fi

		# logo
		echo -e ".." >> _n/_tot
		if [ -n "`find _z -name pack.png -type f`" ]; then
			# fix aspect ratio
			#convert "`find _z -name pack.png -type f | head -n 1`" -gravity North -resize 128x128 -background none -extent 160x148 screenshot.png
			cp "`find _z -name pack.png -type f | head -n 1`" screenshot.png
			echo -e ".." >> _n/_counter
		elif [ -f _n/blocks/grass_side.png -a -f _n/dirt.png ]; then
			# make something up
			montage -geometry +0+0 _n/blocks/grass_side.png _n/blocks/grass_side.png _n/blocks/grass_side.png _n/blocks/grass_side.png \
				_n/blocks/dirt.png _n/blocks/dirt.png _n/blocks/dirt.png _n/blocks/dirt.png \
				_n/blocks/dirt.png _n/blocks/dirt.png _n/blocks/dirt.png _n/blocks/dirt.png screenshot.png
		fi

		count=`cat _n/_counter | wc -c`
		tot=`cat _n/_tot | wc -c`
		echo "$n ${PXSIZE}px [$((100 * count / tot))%]" > description.txt
		echo "(Converted from $n with Minetest Texture and Resource Pack Converter)" >> description.txt
		echo "   - Conversion quality: $count / $tot"
		if [ -n "$PXSIZE" ]; then
			echo "   - Pixel size: ${PXSIZE}px"
		fi
		if [ -f _z/pack.txt ]; then
			echo "Original Description:" >> description.txt
			cat _z/pack.txt >> description.txt
		fi
		rm -rf _z _n
	)
}

if [ -n "$NOGUI" ]; then
	choice=$1
	if [ -z "$choice" ]; then
		choice=all
	elif [ "$choice" != all ] && [ "$choice" != default ]; then
		convert_file "$@"
		exit $?
	fi
else
	choice=`$ZENITY --list --title "Choose resource packs to convert" --column="Convert" \
	--text "Do you want to convert installed resource packs, or convert a single zip file?" \
	--column="Description" --height 400 \
	"all" "Find Minecraft resource packs installed in your minecraft folders and convert those automatically" \
	"default" "Convert the default resource pack" \
	"other" "Choose a file to convert manually" 2> /dev/null`
fi

if [ "$choice" == "all" ]; then
	echo "Automatically converting resourcepacks and texturepacks found..."

	echo "Scanning for texture/resourcepacks..."
	(
		find ~/.minecraft/texturepacks/ -name '*.zip'
		find ~/.minecraft/resourcepacks -name '*.zip'
	) | while read f; do
		convert_file "$f"
	done
elif [ "$choice" == "other" ]; then
	# assume file name to zip is passed
	convert_file "`$ZENITY --file-selection --file-filter="*.zip" 2> /dev/null`"
elif [ "$choice" == "default" ]; then
	if ! cp ~/.minecraft/versions/1.9/1.9.jar /tmp/mc-default-1.9.zip ; then
		exit 1
	fi
	convert_file /tmp/mc-default-1.9.zip
	rm /tmp/mc-default-1.9.zip
fi
