class_name ColorVision
extends RefCounted
## How a color looks with the three common color blindnesses (a missing kind of cone, the strongest
## case: Machado, Oliveira and Fernandes 2009, applied in linear RGB), and how far apart two colors
## look (the distance in OKLab, where 1 is black to white). Used by the palette viewer.

enum Vision { NORMAL, PROTANOPIA, DEUTERANOPIA, TRITANOPIA }

## The linear-RGB matrix per vision, its rows (red, green, blue out) stored as the basis' columns.
const MATRICES: Dictionary[Vision, Basis] = {
	Vision.PROTANOPIA:
	Basis(
		Vector3(0.152286, 1.052583, -0.204868),
		Vector3(0.114503, 0.786281, 0.099216),
		Vector3(-0.003882, -0.048116, 1.051998),
	),
	Vision.DEUTERANOPIA:
	Basis(
		Vector3(0.367322, 0.860646, -0.227968),
		Vector3(0.280085, 0.672501, 0.047413),
		Vector3(-0.01182, 0.04294, 0.968881),
	),
	Vision.TRITANOPIA:
	Basis(
		Vector3(1.255528, -0.076749, -0.178779),
		Vector3(-0.078411, 0.930809, 0.147602),
		Vector3(0.004733, 0.691367, 0.3039),
	),
}
const NAMES: Dictionary[Vision, String] = {
	Vision.NORMAL: "Normal",
	Vision.PROTANOPIA: "Protanopia (no red cones)",
	Vision.DEUTERANOPIA: "Deuteranopia (no green cones)",
	Vision.TRITANOPIA: "Tritanopia (no blue cones)",
}


## `color` (sRGB) as seen with `vision`; alpha stays.
static func simulate(color: Color, vision: Vision) -> Color:
	if vision == Vision.NORMAL:
		return color
	var linear: Color = color.srgb_to_linear()
	var rgb: Vector3 = Vector3(linear.r, linear.g, linear.b) * MATRICES[vision]
	var seen := Color(
		clampf(rgb.x, 0.0, 1.0), clampf(rgb.y, 0.0, 1.0), clampf(rgb.z, 0.0, 1.0), color.a
	)
	return seen.linear_to_srgb()


## `color` (sRGB) in OKLab: lightness, green to red, blue to yellow.
static func oklab(color: Color) -> Vector3:
	var c: Color = color.srgb_to_linear()
	var l: float = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b
	var m: float = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b
	var s: float = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b
	l = pow(maxf(l, 0.0), 1.0 / 3.0)
	m = pow(maxf(m, 0.0), 1.0 / 3.0)
	s = pow(maxf(s, 0.0), 1.0 / 3.0)
	return Vector3(
		0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
	)


## How different `a` and `b` look with `vision` (OKLab distance; alpha ignored).
static func distance(a: Color, b: Color, vision: Vision = Vision.NORMAL) -> float:
	return oklab(simulate(a, vision)).distance_to(oklab(simulate(b, vision)))
