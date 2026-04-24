local Result = require("@pkg/luau_result")

-- type Node<T> = {
--     id: string;
--     value: T?;
--     parent: Node<any>?;
--     children: { [string]: Node<any> };
-- }

type Node<T = any> = {
    id: string;
    value: T;
    parent: Node?;
    children: { [string]: Node };
}

local function construct_node<T>(id: string, value: T, parent: Node?, children: { [string]: Node }?): Node<T>
    return {
        id = id;
        value = value;
        parent = parent;
        children = children or {};
    }
end

local VirtualWorkspace = {}
local VirtualWorkspacePrototype = {
    __index = VirtualWorkspace;
}
table.freeze(VirtualWorkspacePrototype)

export type VirtualWorkspace = setmetatable<{
    read _root: Node<nil>;
}, typeof(VirtualWorkspacePrototype)>

--- Checks if a value is a VirtualWorkspace
local function is(value: unknown): boolean
    return type(value) == "table" and getmetatable(value) == VirtualWorkspacePrototype
end

--- Constructs a new VirtualWorkspace
local function new(): VirtualWorkspace
    return setmetatable(
        {
            _root = construct_node("root", nil);
        },
        VirtualWorkspacePrototype
    )
end

local function traverse<T>(self: VirtualWorkspace, path: string, create_if_missing: boolean): Result.Result<Node<T>, string>
    local current_node = self._root

    for part in string.gmatch(path, "[^/]+") do
        if not current_node.children[part] then
            if create_if_missing then
                local new_node = construct_node(part, nil, current_node, nil)

                current_node.children[part] = new_node
            else
                return Result.err(`Path not found: { path }`)
            end
        end

        current_node = current_node.children[part]
    end

    return Result.ok(current_node)
end

function VirtualWorkspace.set<T>(self: VirtualWorkspace, value: T, path: string): Result.Result<T, string>
    local res = traverse<<T>>(self, path, true)
    local node, err = res:unpack()

    if res:is_err() then
        return Result.err(err)
    end

    if value == nil then
        return Result.err("Given value is nil. Use :remove(path: string) instead.")
    else
        node.value = value
    end

    return Result.ok(value)
end

function VirtualWorkspace.remove<T>(self: VirtualWorkspace, path: string): Result.Result<T, string>
    local res = traverse<<T>>(self, path, false)
    local node, err = res:unpack()

    if res:is_err() then
        return Result.err(err)
    end

    local value = node.value
    node.value = nil

    if next(node.children) == nil and node.parent then
        node.parent.children[node.id] = nil
    end

    return Result.ok(value)
end

function VirtualWorkspace.get<T>(self: VirtualWorkspace, path: string): Result.Result<T?, string>
    local res = traverse<<T>>(self, path, false)
    local node, err = res:unpack()

    if res:is_err() then
        if err:find("^Path not found") then
            return Result.ok(nil)
        else
            return Result.err(err)
        end
    end

    return Result.ok(node.value)
end

export type Located<T> = {
    id: string;
    path: string;
    value: T
}

function VirtualWorkspace.get_children<T>(self: VirtualWorkspace, path: string): Result.Result<{ Located<T> }, string>
    local res = traverse(self, path, false)
    local node, err = res:unpack()

    if res:is_err() then
        if err:find("^Path not found") then
            return Result.ok({})
        else
            return Result.err(err)
        end
    end

    local children: { Located<T> } = {}

    for id, child_node: Node<T> in node.children do
        children[#children + 1] = {
            id = id;
            path = path .. "/" .. id;
            value = child_node.value;
        }
    end

    return Result.ok(children)
end

function VirtualWorkspace.clear_all_children<T>(self: VirtualWorkspace, path: string): Result.Result<{ Located<T> }, string>
    local res = traverse(self, path, false)
    local node, err = res:unpack()

    if res:is_err() then
        return Result.err(err)
    end

    local children: { Located<T> } = {}

    for id, child_node: Node<T> in node.children do
        children[#children + 1] = {
            id = id;
            path = path .. "/" .. id;
            value = child_node.value;
        }
    end

    return Result.ok(children)
end

function VirtualWorkspace.get_descendants<T>(self: VirtualWorkspace, path: string): Result.Result<{ Located<T> }, string>
    local res = traverse(self, path, false)
    local node, err = res:unpack()

    if res:is_err() then
        return Result.err(err)
    end

    local descendants: { Located<T> } = {}

    local function recurse(current_node: Node, current_path: string)
		for id, child_node in current_node.children do
			local child_path = current_path .. "/" .. id
			
			if child_node.value ~= nil then
				descendants[#descendants + 1] = {
                    id = id;
                    path = child_path;
                    value = child_node.value;
                }
			end
			
			recurse(child_node, current_path)
		end
	end

	recurse(node, path)

    return Result.ok(descendants)
end

function VirtualWorkspace.move<T>(self: VirtualWorkspace, origin_path: string, to_path: string): Result.Result<T, string>
    local res = traverse<<T>>(self, origin_path, false)
    local origin_node, err = res:unpack()

    if res:is_err() then
        return Result.err(err)
    end

    if not origin_node.parent then
        return Result.err("Cannot move root directory")
    end

    local to_parent_path = string.match(to_path, "^(.*)/[^/]+$") or ""
    local new_id = string.match(to_path, "[^/]+$")

    if not new_id then
        return Result.err("Invalid destination path")
    end

    local res = traverse<<T>>(self, to_parent_path, true)
    local target_parent_node, err = res:unpack()

    if res:is_err() then
        return Result.err(err)
    end

    if target_parent_node.children[new_id] then
        return Result.err("Destination already exists")
    end

    origin_node.parent.children[origin_node.id] = nil
    origin_node.parent = target_parent_node
    origin_node.id = new_id
    target_parent_node.children[new_id] = origin_node

    return Result.ok(origin_node.value)
end

--- Class VirtualWorkspace
return {
    is = is;
    new = new;
}