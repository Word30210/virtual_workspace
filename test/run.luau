local fs = require("@lune/fs")
local frktest = require("@lune_pkg/frktest")
local console_reporter = frktest._reporters.lune_console_reporter

local lib_content = fs.readFile("./src/lib.luau")
local built_content = string.gsub(lib_content, "<<.->>", "")

fs.writeFile("./src/lib.built.luau", built_content)

local built_lib = (require :: any)("../src/lib.built")

local success, file_paths = pcall(fs.readDir, "test")

if not success then
	error("tests are missing. Make sure you run this from the project root directory.")
end

for _, file_path in next, file_paths do
	local luau_file_path = string.match(file_path, "(.-)%.luau$")

	if not luau_file_path then
		continue
	end

	if string.find(luau_file_path, "^run$") then
		continue
	end

	(require :: any)(`./{ luau_file_path }`)(built_lib)
end

console_reporter.init()
frktest.run()

pcall(fs.removeFile, "./src/lib.built.luau")

return nil