function table.removeKey(t, k)
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

function splitStringToTable(inputString, splitter)
    local ret = {};
    local tmp;

    if inputString == nil then return nil; end

    if (splitter == nil) then
        table.insert(ret, inputString);
        return ret;
    end

    -- print("inputString: " .. inputString .. ", splitter:" .. splitter);
    local found = true;
    while found do
        local s,e = inputString:find(splitter);
        if s == nil then
            table.insert(ret, inputString);
            found = false;
        else
            -- print("s/e=" .. s .. "/" .. e);
            tmp = inputString:sub(0,s - 1);
            table.insert(ret, tmp);
            inputString = inputString:sub(e + 1);
        end
    end
    -- for k,v in pairs(ret) do print(k,v) end
    return ret;
end


function tableLength(table)
    if (table == nil) then return 0; end
    local count = 0
    for _ in pairs(table) do count = count + 1 end
    return count
end

function clamp(value, min, max)
    if value == nil then return nil; end
    if max == nil and min == nil then return value; end
    if min == nil then return math.min(value, max); end
    if max == nil then return math.max(value, min); end
    return math.max(math.min(value, max), min);
end

function toNum(number, default)
    default = default or 0;
    return tonumber(number) or default;
end

function randomCheck(normalizedIntProb, minValue, maxValue)
    minValue = toNum(minValue, 1);
    maxValue = toNum(maxValue, 100);
    return math.random(1,100) <= toNum(normalizedIntProb);
end
