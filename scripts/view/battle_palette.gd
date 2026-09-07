extends RefCounted

## Immutable BattleView color projections. Kept separate so the input/render
## adapter remains under the repository's 1,000-line file budget.

const ENEMY_TYPE := {
	&"grunt": Color("ef7d57"),
	&"runner": Color("f4d35e"),
	&"shieldbearer": Color("c98f65"),
	&"breacher": Color("c66b5d"),
	&"heavy": Color("b13e53"),
	&"drone": Color("73eff7"),
	&"interceptor": Color("69b9d0"),
	&"spellcaster": Color("c964cf"),
	&"mini_boss": Color("94216a"),
}

const OPERATOR_CLASS := {
	OperatorDef.OpClass.VANGUARD: Color("38b764"),
	OperatorDef.OpClass.GUARD: Color("a7f070"),
	OperatorDef.OpClass.DEFENDER: Color("257179"),
	OperatorDef.OpClass.SNIPER: Color("ffcd75"),
	OperatorDef.OpClass.CASTER: Color("5d275d"),
	OperatorDef.OpClass.HEALER: Color("a7f070"),
	OperatorDef.OpClass.RECRUIT: Color("38b764"),
}
