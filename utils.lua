function treasure_chest.removeKey(t, k)
	local i = 0
	local keys, values = {},{}
	for k,v in pairs(t) do
		i = i + 1
		keys[i] = k
		values[i] = v
	end

	while i>0 do
		if keys[i] == k then
			table.remove(keys, i)
			table.remove(values, i)
			break
		end
		i = i - 1
	end

	local a = {}
	for i = 1,#keys do
		a[keys[i]] = values[i]
	end

	return a
end

function treasure_chest.clamp(value, min, max)
    if value == nil then return nil; end
    if max == nil and min == nil then return value; end
    if min == nil then return math.min(value, max); end
    if max == nil then return math.max(value, min); end
    return math.max(math.min(value, max), min);
end

function treasure_chest.toNum(number, default)
    default = default or 0;
    return tonumber(number) or default;
end

function treasure_chest.randomCheck(normalizedIntProb, minValue, maxValue)
    minValue = treasure_chest.toNum(minValue, 1);
    maxValue = treasure_chest.toNum(maxValue, 100);
    return math.random(1,100) <= treasure_chest.toNum(normalizedIntProb);
end
