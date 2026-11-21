-- Builds quest routes and calculates XP without client UI calls.
local _, addon = ...
local L = addon.L
addon.Core = {}
local Core = addon.Core

local graphBatchSize = 100
local maxRouteDepth = 100
local maxRouteVisits = 2048
local maxRouteCount = 128

local function asList(value)
    return type(value) == "table" and value or {}
end

local function isQuestID(value)
    return type(value) == "number" and value > 0 and value == math.floor(value)
end

local function appendUnique(values, value)
    for _, existing in ipairs(values) do
        if existing == value then
            return
        end
    end
    values[#values + 1] = value
end

-- Only completion prerequisites establish required chain links.
function Core.NewGraph(read, ids, eligible, yieldBatch)
    local graph = { nodes = {}, parents = {}, children = {}, unknown = {} }
    for i, questID in ipairs(ids) do
        if eligible(questID) then
            graph.nodes[questID] = read(questID)
            graph.parents[questID], graph.children[questID] = {}, {}
        end
        if yieldBatch and i % graphBatchSize == 0 then
            yieldBatch()
        end
    end
    local processed = 0
    for questID, row in pairs(graph.nodes) do
        local group = asList(row.group)
        row.parallel = #group > 1
        local prerequisites = #group > 0 and group or asList(row.single)
        for _, parent in ipairs(prerequisites) do
            if isQuestID(parent) then
                local parentRow = graph.nodes[parent]
                if parentRow and not isQuestID(parentRow.breadcrumb) then
                    appendUnique(graph.parents[questID], parent)
                    appendUnique(graph.children[parent], questID)
                elseif not parentRow and eligible(parent) then
                    graph.unknown[questID] = true
                end
            elseif type(parent) == "number" and parent < 0 then
                graph.unknown[questID] = true
            end
        end
        processed = processed + 1
        if yieldBatch and processed % graphBatchSize == 0 then
            yieldBatch()
        end
    end
    -- Breadcrumbs point forward but are optional predecessors.
    for questID, row in pairs(graph.nodes) do
        if isQuestID(row.breadcrumb) then
            if graph.nodes[row.breadcrumb] then
                appendUnique(graph.children[questID], row.breadcrumb)
            else
                graph.unknown[questID] = true
            end
        end
        table.sort(graph.parents[questID])
        table.sort(graph.children[questID])
        processed = processed + 1
        if yieldBatch and processed % graphBatchSize == 0 then
            yieldBatch()
        end
    end
    return graph
end

-- Keep parallel requirements scoped to this quest and its next steps.
local function parallelRequirements(graph, questID)
    local context = { followups = {}, prerequisites = {} }
    for _, nextID in ipairs(graph.children[questID]) do
        local requirements = {}
        for _, prerequisite in ipairs(asList(graph.nodes[nextID].group)) do
            if isQuestID(prerequisite) and prerequisite ~= questID then
                appendUnique(requirements, prerequisite)
            end
        end
        table.sort(requirements)
        context.followups[#context.followups + 1] = { questID = nextID, requirements = requirements }
    end
    if graph.nodes[questID].parallel then
        for _, prerequisite in ipairs(asList(graph.nodes[questID].group)) do
            if isQuestID(prerequisite) then
                appendUnique(context.prerequisites, prerequisite)
            end
        end
        table.sort(context.prerequisites)
    end
    return context
end

-- Trace routes through the selected quest; preserve AND prerequisites.
function Core.Routes(graph, questID, isCompleted)
    if not graph.nodes[questID] then
        return { status = "unknown" }
    end
    local failure, visits = nil, 0
    local function walk(current, direction, seen, depth)
        visits = visits + 1
        depth = (depth or 0) + 1
        -- Bound malformed or heavily branching data before it can stall the UI.
        if depth > maxRouteDepth or visits > maxRouteVisits or seen[current] then
            failure = "complex"
            return {}
        end
        if graph.unknown[current] then
            failure = "incomplete"
            return {}
        end
        if graph.nodes[current].parallel then
            failure = "parallel"
            return {}
        end
        seen[current] = true
        local neighbors = graph[direction][current]
        if direction == "parents" and #neighbors > 1 then
            local completed = {}
            for _, parent in ipairs(neighbors) do
                if isCompleted(parent) then
                    completed[#completed + 1] = parent
                end
            end
            if #completed == 1 then
                neighbors = completed
            end
        end
        local paths = {}
        if #neighbors == 0 then
            paths[1] = { current }
        end
        for _, nextID in ipairs(neighbors) do
            for _, path in ipairs(walk(nextID, direction, seen, depth)) do
                local result = { current }
                for _, value in ipairs(path) do
                    result[#result + 1] = value
                end
                paths[#paths + 1] = result
                if #paths > maxRouteCount then
                    failure = "complex"
                    break
                end
            end
            if failure then
                break
            end
        end
        seen[current] = nil
        return paths
    end
    local before, after = walk(questID, "parents", {}), walk(questID, "children", {})
    if failure then
        return { status = failure, context = failure == "parallel" and parallelRequirements(graph, questID) or nil }
    end
    local routes = {}
    for _, back in ipairs(before) do
        for _, forward in ipairs(after) do
            local route, seen = {}, {}
            for i = #back, 1, -1 do
                route[#route + 1] = back[i]
                seen[back[i]] = true
            end
            for i = 2, #forward do
                if seen[forward[i]] then
                    return { status = "complex" }
                end
                route[#route + 1] = forward[i]
            end
            routes[#routes + 1] = { ids = route, step = #back }
            if #routes > maxRouteCount then
                return { status = "complex" }
            end
        end
    end
    return { status = "known", routes = routes }
end

function Core.AdjustXP(base, questLevel, playerLevel, maxLevel)
    if maxLevel and playerLevel >= maxLevel then
        return 0
    end
    if type(base) ~= "number" or base < 0 then
        return nil
    end
    if base == 0 then
        return 0
    end
    if not questLevel or questLevel <= 0 then
        return nil
    end
    local xp = base * math.max(1, math.min(10, 2 * (questLevel - playerLevel) + 20)) / 10
    local unit = xp <= 100 and 5 or xp <= 500 and 10 or xp <= 1000 and 25 or 50
    return math.floor(xp / unit + 0.5) * unit
end

local function formatNumber(value)
    return L.Number(value)
end

local function formatRange(minimum, maximum, grouped)
    local format = grouped and formatNumber or tostring
    if minimum == maximum then
        return format(minimum)
    end
    return format(minimum) .. "-" .. format(maximum)
end
local separator = " \194\183 "
local function formatXP(minimum, maximum, unknown, estimated)
    if unknown then
        return L["Unknown"]
    end
    return L.Format("%s XP", formatRange(minimum, maximum, true))
end
local statusLabels = {
    unknown = L["Chain unknown"],
    incomplete = L["Chain data missing"],
    parallel = L["Requires other quests"],
    complex = L["Chain unknown"],
    loading = L["Loading..."],
}

local function describeRelationships(context, isCompleted, getQuestName, getXP)
    local function name(id)
        return getQuestName and getQuestName(id) or L.Format("Quest %s", id)
    end
    local function describe(ids)
        local result = {}
        for _, id in ipairs(ids) do
            result[#result + 1] = { questID = id, name = name(id), completed = isCompleted(id) }
        end
        return result
    end
    local followups, estimated = {}, false
    for _, followup in ipairs(context.followups) do
        local xp, estimate = getXP(followup.questID)
        local reward = xp == nil and L["XP unknown"] or formatXP(xp, xp, false, estimate)
        local quest = name(followup.questID)
        estimated = estimated or (xp ~= nil and estimate)
        followups[#followups + 1] = {
            name = quest,
            label = quest .. " [" .. reward .. "]",
            requirements = describe(followup.requirements),
        }
    end
    local label
    if #followups == 0 then
        label = L["Final step"]
    elseif #followups > 1 then
        label = L.Format("Leads to %d follow-ups", #followups)
    else
        local nextQuest = followups[1]
        label = L.Format("Leads to %s", nextQuest.label)
        local requirements, remaining, unknown = nextQuest.requirements, {}, false
        for _, requirement in ipairs(requirements) do
            if requirement.completed ~= true then
                remaining[#remaining + 1] = requirement
            end
            if requirement.completed == nil then
                unknown = true
            end
        end
        if #requirements == 1 and #remaining == 0 then
            label = label .. separator .. L.Format("%s done", requirements[1].name)
        elseif #requirements > 1 and #remaining == 0 then
            label = label .. separator .. L["other quests done"]
        elseif #remaining == 1 then
            label = label .. separator .. L.Format(unknown and "also requires %s" or "also needs %s", remaining[1].name)
        elseif #remaining > 1 then
            label = label
                .. separator
                .. L.Format(unknown and "also requires %d quests" or "also needs %d quests", #remaining)
        end
    end
    return label, followups, describe(context.prerequisites), estimated
end

function Core.Summary(result, questID, getXP, isCompleted, getQuestName)
    local current, currentEstimate = getXP(questID)
    local currentText = formatXP(current, current, current == nil, currentEstimate)
    if result.status ~= "known" then
        local label = statusLabels[result.status] or L["Chain unknown"]
        local followups, prerequisites, followupEstimate
        if result.context then
            label, followups, prerequisites, followupEstimate =
                describeRelationships(result.context, isCompleted, getQuestName, getXP)
        end
        local reward = current == nil and L["XP unknown this quest"] or L.Format("%s this quest", currentText)
        return {
            text = label .. separator .. reward,
            progress = label,
            currentXP = currentText,
            estimated = currentEstimate or followupEstimate,
            status = result.status,
            followups = followups,
            prerequisites = prerequisites,
        }
    end
    local minStep, maxStep, minCount, maxCount = math.huge, 0, math.huge, 0
    local minAfter, maxAfter, minRemaining, maxRemaining = math.huge, 0, math.huge, 0
    local unknownAfter, estimateAfter, final = false, false, true
    for _, route in ipairs(result.routes) do
        minStep, maxStep = math.min(minStep, route.step), math.max(maxStep, route.step)
        minCount, maxCount = math.min(minCount, #route.ids), math.max(maxCount, #route.ids)
        final = final and route.step == #route.ids
        local after, remaining = 0, 1
        -- Count unpaid XP, including quests ready to turn in.
        for i = route.step + 1, #route.ids do
            local futureID = route.ids[i]
            if not isCompleted(futureID) then
                local xp, estimated = getXP(futureID)
                if xp == nil then
                    unknownAfter = true
                else
                    after = after + xp
                end
                estimateAfter = estimateAfter or estimated
                remaining = remaining + 1
            end
        end
        minAfter, maxAfter = math.min(minAfter, after), math.max(maxAfter, after)
        minRemaining, maxRemaining = math.min(minRemaining, remaining), math.max(maxRemaining, remaining)
    end
    local standalone = maxCount == 1
    local position, count = formatRange(minStep, maxStep), formatRange(minCount, maxCount)
    local steps = standalone and L["Standalone"] or final and L["Final step"] or L.Format("Step %s/%s", position, count)
    local unknownLeft = current == nil or unknownAfter
    local estimated = currentEstimate or estimateAfter
    local left = formatXP((current or 0) + minAfter, (current or 0) + maxAfter, unknownLeft, estimated)
    local reward = unknownLeft and L["Remaining XP unknown"] or L.Format("%s left", left)
    if standalone or final then
        reward = current == nil and L["XP unknown"] or currentText
    end
    local remainingText = L.Format(
        maxRemaining == 1 and "%s quest remaining" or "%s quests remaining",
        formatRange(minRemaining, maxRemaining)
    )
    return {
        text = steps .. separator .. reward,
        status = "known",
        routes = result.routes,
        progress = standalone and L["Standalone quest"]
            or L.Format("Step %s of %s — %s", position, count, remainingText),
        currentXP = currentText,
        afterXP = formatXP(minAfter, maxAfter, unknownAfter, estimateAfter),
        remainingXP = left,
        estimated = estimated,
        standalone = standalone,
    }
end

-- Format XP for one quest, not the full chain.
function Core.QuestXPText(xp)
    if xp == nil then
        return L["unknown XP"]
    end
    if xp == 0 then
        return L["no XP"]
    end
    return L.Format("%s XP", formatNumber(xp))
end

-- Reward cards use this amount without parsing a translated XP unit or word order.
function Core.QuestXPAmount(xp)
    return xp == nil and L["Unknown"] or formatNumber(xp)
end

-- Track visited successors to avoid cycles.
function Core.Future(graph, questID, isCompleted)
    local result, seen, queue = {}, { [questID] = true }, { questID }
    local cursor = 1
    while graph and cursor <= #queue do
        for _, child in ipairs(graph.children[queue[cursor]] or {}) do
            if not seen[child] then
                seen[child] = true
                queue[#queue + 1] = child
                if not isCompleted(child) then
                    result[#result + 1] = child
                end
            end
        end
        cursor = cursor + 1
    end
    return result
end

-- Collect one prerequisite set without counting shared ancestors twice.
local function requiredAncestors(graph, rootID)
    local included, active, count = {}, {}, 0
    local function visit(currentID, depth)
        if active[currentID] or depth > maxRouteDepth or graph.unknown[currentID] or not graph.nodes[currentID] then
            return false
        end
        if included[currentID] then
            return true
        end
        included[currentID] = true
        active[currentID] = true
        count = count + 1
        if count > maxRouteVisits then
            return false
        end
        local parents = graph.parents[currentID] or {}
        -- Multiple alternative prerequisites do not establish one exact total.
        if #parents > 1 and not graph.nodes[currentID].parallel then
            return false
        end
        for _, parent in ipairs(parents) do
            if not visit(parent, depth + 1) then
                return false
            end
        end
        active[currentID] = nil
        return true
    end
    if visit(rootID, 1) then
        return included, count
    end
end

function Core.StepText(graph, questID, routes)
    if routes.status == "known" then
        local minStep, maxStep, minCount, maxCount = math.huge, 0, math.huge, 0
        for _, route in ipairs(routes.routes) do
            minStep, maxStep = math.min(minStep, route.step), math.max(maxStep, route.step)
            minCount, maxCount = math.min(minCount, #route.ids), math.max(maxCount, #route.ids)
        end
        return formatRange(minStep, maxStep) .. "/" .. formatRange(minCount, maxCount)
    end
    -- Required parallel quests share the terminal quest's prerequisite set.
    -- Independent branches can be completed in either order, so show a range.
    if routes.status == "parallel" and graph then
        local future = Core.Future(graph, questID, function()
            return false
        end)
        local terminal
        for _, currentID in ipairs(future) do
            if graph.unknown[currentID] then
                return "?/?"
            end
            if #(graph.children[currentID] or {}) == 0 then
                if terminal then
                    return "?/?"
                end
                terminal = currentID
            end
        end
        if not terminal then
            if #(graph.children[questID] or {}) > 0 then
                return "?/?"
            end
            terminal = questID
        end
        local required, total = requiredAncestors(graph, terminal)
        local before, earliest = requiredAncestors(graph, questID)
        if not required or not before or not required[questID] then
            return "?/?"
        end
        local after = 0
        for _, currentID in ipairs(future) do
            if not required[currentID] then
                return "?/?"
            end
            after = after + 1
        end
        return formatRange(earliest, total - after) .. "/" .. total
    end
    return "?/?"
end
