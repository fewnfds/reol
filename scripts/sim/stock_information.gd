class_name SimStockInformation
extends RefCounted
## A statement's occurrence is a fact; its contents are a person's claim.
## Queries use only that observer's memories and attributed statements, never
## current warehouse truth. Reuses the existing saved event/provenance ledger.


static func valid_policy(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1:
		return false
	for field: String in ["direct_protection_minutes", "memory_lifetime_minutes", "repeat_statement_minutes"]:
		if not _count(data.get(field)) or int(data[field]) < 1:
			return false
	var trust: Variant = data.get("minimum_source_reliability")
	return (trust is int or trust is float) and is_finite(float(trust)) and float(trust) >= 0.0 and float(trust) <= 1.0 and int(data.direct_protection_minutes) <= int(data.memory_lifetime_minutes)


static func assess(sim: RefCounted, observer: String, place: String, item: String, policy: Dictionary) -> Dictionary:
	if not sim.has_actor(observer) or not sim.places.has(place):
		return {"known": false, "conflicted": false, "accounts": []}
	var accounts: Array[Dictionary] = []
	var selected: Dictionary = {}
	var direct: Dictionary = sim.actor_state(observer).stock_memory.get(place, {})
	if not direct.is_empty() and sim.tick_index - int(direct.tick) <= int(policy.memory_lifetime_minutes):
		selected = {"amount": int(direct.items.get(item, 0)), "at": int(direct.tick),
			"basis": "observed", "source": observer, "credible": true, "event": ""}
		accounts.append(selected.duplicate(true))
	for event_id: String in sim.social.knowledge[observer]:
		var known: Dictionary = sim.social.knowledge[observer][event_id]
		var details: Dictionary = known.details
		if known.kind != "stock_statement" or details.get("location") != place or details.get("item") != item or known.actor == observer:
			continue
		if not _count(details.get("amount")) or sim.tick_index - int(known.tick) > int(policy.memory_lifetime_minutes):
			continue
		var source: String = str(known.actor) if bool(known.direct) else str(known.source)
		var credible: bool = float(sim.social.relation(observer, source).reliability) >= float(policy.minimum_source_reliability)
		var account: Dictionary = {"amount": int(details.amount), "at": int(known.tick),
			"basis": "said", "source": source, "stated_by": str(known.actor), "credible": credible, "event": event_id}
		accounts.append(account)
		if not credible:
			continue
		# Recent personal inspection outweighs a conflicting report. Once stale,
		# newer credible testimony may guide action, even if it is actually false.
		if not selected.is_empty():
			if selected.basis == "observed" and sim.tick_index - int(selected.at) <= int(policy.direct_protection_minutes):
				continue
			if int(account.at) < int(selected.at):
				continue
			if int(account.at) == int(selected.at) and event_id.get_slice("_", 1).to_int() <= str(selected.event).get_slice("_", 1).to_int():
				continue
		selected = account.duplicate(true)
	var values: Dictionary = {}
	for account: Dictionary in accounts:
		values[str(account.amount)] = true
	var result: Dictionary = {"known": not selected.is_empty(), "conflicted": values.size() > 1, "accounts": accounts}
	if not selected.is_empty():
		result.merge(selected, true)
	return result


static func tell(sim: RefCounted, speaker: String, listener: String, place: String, item: String, amount: int, policy: Dictionary) -> Dictionary:
	if speaker == listener or not sim.has_actor(speaker) or not sim.has_actor(listener) or not sim.places.has(place) or item.is_empty() or amount < 0 or amount > SimInventory.MAX_COUNT:
		return {"ok": false, "line": "暂时无法谈论这件事。"}
	if not bool(sim.actor_state(speaker).alive) or not bool(sim.actor_state(listener).alive) or sim._distance(speaker, listener) > float(sim.config.talk_radius):
		return {"ok": false, "line": "先走近些，才能当面说话。"}
	# Repeated clicks reuse the real utterance, without new memory/events or RNG.
	for index in range(sim.social.events.size() - 1, -1, -1):
		var event: Dictionary = sim.social.events[index]
		if sim.tick_index - int(event.tick) > int(policy.repeat_statement_minutes):
			continue
		if event.kind != "stock_statement" or event.actor != speaker or event.target != listener:
			continue
		var old: Dictionary = event.details.get("participants", {})
		if old.get("location") == place and old.get("item") == item:
			if old.get("amount") == amount:
				return {"ok": true, "event": event.id, "repeated": true, "line": "这句话已经说过；对方仍会按自己的见闻判断。"}
			break
	var witnesses: Array[String] = []
	var event_id: String = sim.social.record("stock_statement", speaker, listener,
		{"participants": {"location": place, "item": item, "amount": amount}}, witnesses, sim.tick_index)
	return {"ok": not event_id.is_empty(), "event": event_id, "repeated": false, "line": "对方听到了这番说法；是否采信，还要看他的见闻。"}


static func valid_statement(event: Dictionary, places: Dictionary) -> bool:
	if event.actor == event.target or str(event.target).is_empty():
		return false
	var details: Variant = event.details.get("participants")
	return details is Dictionary and places.has(details.get("location")) and details.get("item") is String and not str(details.item).is_empty() and _count(details.get("amount"))


static func _count(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= SimInventory.MAX_COUNT and float(value) == floorf(float(value))
