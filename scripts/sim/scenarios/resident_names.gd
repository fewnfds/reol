extends RefCounted
## Generate names at scenario assembly. The actor record keeps the result on save.
const SURNAMES: Array[String] = [
	"沈", "顾", "陆", "谢", "林", "许", "苏", "柳", "叶", "贺", "温", "江", "周", "程", "秦", "何",
	"裴", "傅", "孟", "陈", "梁", "唐", "陶", "卫", "钟", "洛", "宁", "宋", "白", "云", "于", "徐",
	"韩", "方", "杜", "姚", "萧", "魏", "凌", "罗", "欧阳", "司马", "慕容", "诸葛", "上官", "南宫",
]
const MALE_GIVEN: String = "修远怀瑾明砚渊行柏庭谦玄晏朗弘昭岳衡崇屹松朔弈峥昀承哲景"
const FEMALE_GIVEN: String = "清婉若兰晴棠宛仪芷蘅绮韶宜瑶岚微汀菀凝韵芙菱月筠娴芸翎蓁韫宁"
const GIVEN_TAIL: String = "安之宁舟澄初雪青华溪容知音竹露秋诗微禾潭川林霜心风书云庭"


static func generate(random: RandomNumberGenerator, sex: String) -> String:
	var surname: String = SURNAMES[random.randi_range(0, SURNAMES.size() - 1)]
	var letters: String = FEMALE_GIVEN if sex == "female" else MALE_GIVEN
	var given: String = letters[random.randi_range(0, letters.length() - 1)]
	if random.randf() < 0.75:
		var tail: String = GIVEN_TAIL[random.randi_range(0, GIVEN_TAIL.length() - 1)]
		if tail != given: given += tail
	return surname + given
