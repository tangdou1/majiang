class_name NameGen
extends RefCounted
## 随机生成真实感的中文昵称（AI 玩家用），每局开始时为三位 AI 各取一个不重复的名字。

const SURNAMES := [
	"王", "李", "张", "刘", "陈", "杨", "赵", "黄", "周", "吴",
	"徐", "孙", "胡", "朱", "高", "林", "何", "郭", "马", "罗",
	"梁", "宋", "郑", "谢", "韩", "唐", "冯", "于", "董", "萧",
]

const GIVEN := [
	"伟", "磊", "强", "军", "勇", "杰", "涛", "峰", "鹏", "辉",
	"刚", "明", "亮", "龙", "斌", "浩", "宇", "帆", "凯", "昊",
	"娜", "芳", "敏", "静", "丽", "艳", "婷", "雪", "悦", "慧",
	"欣", "怡", "琳", "倩", "瑶", "晨", "然", "思远", "子轩", "雨桐",
	"嘉怡", "浩然", "若曦", "梓涵", "俊熙", "欣妍", "文博", "一鸣", "小雨", "小北",
]

const NICKNAMES := [
	"大强", "老王", "小鱼", "阿橘", "胖虎", "牌神小林", "麻将小王子", "川妹子",
	"二哥", "三姐", "阿杰", "小美", "阿明", "老陈", "燕子", "山城老炮",
]


## 返回 count 个互不相同的名字
static func pick(count: int, rng: RandomNumberGenerator = null) -> Array[String]:
	var r := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	var out: Array[String] = []
	var used := {}
	var guard := 0
	while out.size() < count and guard < 200:
		guard += 1
		var name := ""
		if r.randf() < 0.25:
			name = NICKNAMES[r.randi() % NICKNAMES.size()]
		else:
			name = SURNAMES[r.randi() % SURNAMES.size()] + GIVEN[r.randi() % GIVEN.size()]
		if not used.has(name):
			used[name] = true
			out.append(name)
	return out
