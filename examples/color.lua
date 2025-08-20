Color = require("Color")

local col = Color.fromHex("#Ab1289")
if Color.__tostring(col) ~= "#ab1289ff" then
	print("EXPECTED", "#ab1289ff", "BUT GOT", col)
	os.exit(1)
end
