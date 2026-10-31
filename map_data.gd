extends RefCounted
# Roads traced by hand from the user's "FULL MAP (MAKKAH)" picture (map/makkah_map.png).
# Game origin (0,0) = Al Haram. 1 map pixel (3x crop) = 0.8 game units.
const MAP_SCALE := 0.8
const MAP_CENTER_PX := Vector2(615, 432)
const MAP_SIZE_PX := Vector2(1230, 855)
const START_POS := Vector2(-2.4,-105.6)
# [road_width, [points]]
const ROADS := [
	[11.0,[Vector2(-460.0,-277.6),Vector2(-364.0,-177.6),Vector2(-260.0,-89.6),Vector2(-184.0,-29.6)]],
	[11.0,[Vector2(-484.0,90.4),Vector2(-388.0,54.4),Vector2(-292.0,18.4),Vector2(-184.0,-5.6)]],
	[11.0,[Vector2(-388.0,162.4),Vector2(-292.0,102.4),Vector2(-172.0,42.4),Vector2(-140.0,30.4)]],
	[11.0,[Vector2(188.0,30.4),Vector2(308.0,78.4),Vector2(396.0,118.4),Vector2(480.0,166.4)]],
	[8.0,[Vector2(116.0,10.4),Vector2(188.0,30.4)]],
	[8.0,[Vector2(244.0,-233.6),Vector2(308.0,-297.6),Vector2(388.0,-333.6),Vector2(480.0,-341.6)]],
	[8.0,[Vector2(244.0,-233.6),Vector2(276.0,-185.6),Vector2(300.0,-157.6)]],
	[11.0,[Vector2(244.0,-233.6),Vector2(188.0,-265.6),Vector2(116.0,-265.6),Vector2(28.0,-273.6),Vector2(-92.0,-269.6),Vector2(-212.0,-261.6),Vector2(-276.0,-273.6)]],
	[8.0,[Vector2(-36.0,-333.6),Vector2(-48.0,-225.6),Vector2(-44.0,-145.6),Vector2(-20.0,-81.6)]],
	[8.0,[Vector2(200.0,-337.6),Vector2(188.0,-265.6),Vector2(124.0,-181.6),Vector2(68.0,-81.6),Vector2(36.0,-41.6)]],
	[8.0,[Vector2(-36.0,138.4),Vector2(-92.0,166.4),Vector2(-116.0,230.4),Vector2(-164.0,334.4)]],
	[8.0,[Vector2(68.0,150.4),Vector2(84.0,214.4),Vector2(80.0,334.4)]],
	[8.0,[Vector2(-276.0,-273.6),Vector2(-252.0,-185.6),Vector2(-244.0,-81.6),Vector2(-260.0,-25.6),Vector2(-292.0,18.4)]],
	[8.0,[Vector2(-388.0,-17.6),Vector2(-332.0,70.4),Vector2(-292.0,134.4),Vector2(-284.0,126.4)]],
	[8.0,[Vector2(-484.0,214.4),Vector2(-404.0,166.4),Vector2(-356.0,134.4),Vector2(-292.0,102.4)]],
	[8.0,[Vector2(-228.0,-69.6),Vector2(-132.0,-137.6),Vector2(-60.0,-213.6),Vector2(4.0,-245.6)]],
	[8.0,[Vector2(-140.0,-141.6),Vector2(-188.0,-81.6),Vector2(-184.0,-29.6)]],
	[8.0,[Vector2(68.0,-81.6),Vector2(156.0,-157.6),Vector2(132.0,-153.6)]],
	[8.0,[Vector2(188.0,30.4),Vector2(308.0,58.4)]],
	[8.0,[Vector2(-228.0,66.4),Vector2(-292.0,18.4)]],
	[8.0,[Vector2(-460.0,-105.6),Vector2(-364.0,-177.6)]],
	[8.0,[Vector2(244.0,-233.6),Vector2(332.0,-185.6),Vector2(452.0,-193.6)]],
	[8.0,[Vector2(480.0,166.4),Vector2(388.0,214.4),Vector2(308.0,310.4)]],
	[8.0,[Vector2(-348.0,238.4),Vector2(-404.0,166.4)]],
	[8.0,[Vector2(-164.0,334.4),Vector2(-252.0,262.4),Vector2(-348.0,238.4)]],
	[8.0,[Vector2(80.0,334.4),Vector2(188.0,262.4),Vector2(308.0,310.4)]],
	[12.0,[Vector2(185.6,0.0),Vector2(180.9,31.5),Vector2(167.2,61.4),Vector2(145.1,88.3),Vector2(115.7,110.7),Vector2(80.5,127.6),Vector2(41.3,138.0),Vector2(0.0,141.6),Vector2(-41.3,138.0),Vector2(-80.5,127.6),Vector2(-115.7,110.7),Vector2(-145.1,88.3),Vector2(-167.2,61.4),Vector2(-180.9,31.5),Vector2(-185.6,0.0),Vector2(-180.9,-31.5),Vector2(-167.2,-61.4),Vector2(-145.1,-88.3),Vector2(-115.7,-110.7),Vector2(-80.5,-127.6),Vector2(-41.3,-138.0),Vector2(0.0,-141.6),Vector2(41.3,-138.0),Vector2(80.5,-127.6),Vector2(115.7,-110.7),Vector2(145.1,-88.3),Vector2(167.2,-61.4),Vector2(180.9,-31.5),Vector2(185.6,-0.0)]],
	[8.0,[Vector2(0.0,-141.6),Vector2(-2.4,-81.6)]]
]
# [english, arabic, position]
const DISTRICTS := [
	["Al Aziziyah","العزيزية",Vector2(-128.0,-217.6)],
	["Al Adl","العدل",Vector2(178.4,-203.2)],
	["Al Awali","العوالي",Vector2(-397.6,-61.6)],
	["Al Rusayfah","الرصيفة",Vector2(344.0,-109.6)],
	["Al Haram","المسجد الحرام",Vector2(0.0,2.4)],
	["Al Misfalah","المسفلة",Vector2(346.4,4.8)],
	["Al Shisha","الشيشة",Vector2(229.6,120.8)],
	["Al Maabdah","المعيدة",Vector2(-248.0,178.4)],
	["Al Shisha South","الشيشة",Vector2(-18.4,208.8)]
]
