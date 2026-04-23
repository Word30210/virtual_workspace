local Result = require("@pkg/result") -- the result type doesn't work on new solver.
-- so I should change result util to my own result module I made before.

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

local Collection = {}
local CollectionPrototype = {
    __index = Collection;
}
table.freeze(CollectionPrototype)

export type Collection = setmetatable<{
    read _root: Node<nil>;
}, typeof(CollectionPrototype)>

--- Checks if a value is a Collection
local function is(value: unknown): boolean
    return type(value) == "table" and getmetatable(value) == CollectionPrototype
end

--- Constructs a new Collection
local function new(): Collection
    return setmetatable(
        {
            _root = construct_node("root", nil);
        },
        CollectionPrototype
    )
end

local function traverse<T>(self: Collection, path: string, create_if_missing: boolean): Result.Result<Node<T>?, string>
    local current_node = self._root

    for part in string.gmatch(path, "[^/]+") do
        if not current_node.children[part] then
            if create_if_missing then
                local new_node = construct_node(part, nil, current_node, nil)

                current_node.children[part] = new_node
            else
                return Result.Err(`Path not found: { path }`)
            end
        end

        current_node = current_node.children[part]
    end

    return Result.Ok(current_node)
end

function Collection.register<T>(self: Collection, value: T, path: string): Result.Result<T, string>
    local result = traverse(self, path, true)
    local node: Node<T>, err = result:unpack()

    if result:isErr() then
        return Result.Err(err)
    end

    if node.value ~= nil then
            return Result.Err("value already exists")
    end

    node.value = value

    return Result.Ok(value)
end

function Collection.get<T>(self: Collection, path: string): Result.Result<T?, string>
    local result = traverse(self, path, false)
    local node: Node<T>, err = result:unpack()

    if result:isErr() then
        if err:find("^Path not found") then
            return Result.Ok(nil)
        else
            return Result.Err(err)
        end
    end

    return Result.Ok(node.value)
end

function Collection.move<T>(self: Collection, origin_path: string, to_path: string): Result.Result<T, string>
    local result = traverse(self, origin_path, false)
    local origin_node: Node<T>, err = result:unpack()

    if result:isErr() then
        return Result.Err(err)
    end

    if not origin_node.parent then
        return Result.Err("Cannot move root directory")
    end

    local to_parent_path = string.match(to_path, "^(.*)/[^/]+$") or ""
    local new_id = string.match(to_path, "[^/]+$")

    if not new_id then
        return Result.Err("Invalid destination path")
    end

    local result = traverse(self, to_parent_path, true)
    local target_parent_node: Node<T>, err = result:unpack()

    if result:isErr() then
        return Result.Err(err)
    end

    if target_parent_node then
        if target_parent_node.children[new_id] then
            return Result.Err("Destination already exists")
        end

        origin_node.parent.children[origin_node.id] = nil
        origin_node.parent = target_parent_node
        origin_node.id = new_id
        target_parent_node.children[new_id] = origin_node

        return Result.Ok(origin_node.value)
    end

    return Result.Err("Failed to resolve destination")
end

function Collection.unregister<T>(self: Collection, path: string): Result.Result<T, string>
    local result = traverse(self, path, false)
    local node: Node<T>, err = result:unpack()

    if result:isErr() then
        return Result.Err(err)
    end

    if node then
        local value = node.value
        node.value = nil

        if next(node.children) == nil and node.parent then
            node.parent.children[node.id] = nil
        end

        return Result.Ok(value)
    end

    return Result.Err(`Path not found: { path }`)
end

--- Class Collection
return {
    is = is;
    new = new;
}