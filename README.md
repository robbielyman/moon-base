# moon-base
Zig framework for generating Lua modules from Zig code, 
inspired by [ziggy-pydust] and powered by [ziglua].

moon-base is still very much a work in progress!
contributions and feedback are very welcome.
this README will evolve with the project, assuming it matures.
for now, check the `examples` folder for how to write code using moon-base.

to use the `examples/color.zig` file from Lua,
for instance, on my Mac computer, I can run the following:

```bash
zig build examples
cp zig-out/lib/libcolor.dylib Color.so
lua
```

this launches the Lua interpreter.
here is an example of using the resulting `Color` type:

```lua
Color = require 'Color'
a = Color.fromHex("#991500")
b = Color.fromHex("#110046")
print(a + b)
```

which will output `#aa1546ff`.

[ziggy-pydust]: https://github.com/spiraldb/ziggy-pydust
[ziglua]: https://github.com/natecraddock/ziglua
