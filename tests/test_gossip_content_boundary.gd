extends RefCounted
const Gossip = preload('res://scripts/sim/gossip_network.gd')
static func run() -> Dictionary:
	var g = Gossip.new(19)
	var results: Dictionary = {}
	for kind in ['panic', 'drinking']:
		var disabled = {'mental_health':false,'addiction':false}
		var enabled = {'mental_health':true,'addiction':true}
		results[kind + '_disabled'] = g.observe('w','s',kind,10.0,disabled) == 0
		results[kind + '_enabled'] = g.observe('w','s',kind,10.0,enabled) > 0
	results['self_witness'] = g.observe('w','w','fight',11.0,{}) == 0
	results['empty_witness'] = g.observe('', 's','fight',11.0,{}) == 0
	var ok = true
	for value in results.values():
		ok = ok and value
	return {'ok':ok,'checks':results.size(),'results':results,'rumors':g.rumors.size()}
