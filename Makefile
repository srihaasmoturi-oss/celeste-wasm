# --- Config ---
STATICS_RELEASE=265e23ca-337c-4e8d-b383-0e1e87300468
DOTNETFLAGS=--nodereuse:false -v n /p:SignAssembly=false

# Adjust for CI environment
ifeq ($(CI), true)
    DOTNETFLAGS += /p:EnableDefaultItems=false
    DOTNET_CMD=$(shell which dotnet)
else
    DOTNET_CMD=dotnet
endif

# Debugging: show which dotnet Makefile sees
$(info DOTNET_CMD=$(DOTNET_CMD))
$(info PATH=$(PATH))

# --- Download static dependencies ---
statics:
	mkdir -p statics
	wget https://github.com/r58Playz/FNA-WASM-Build/releases/download/$(STATICS_RELEASE)/FAudio.a -O statics/FAudio.a
	wget https://github.com/r58Playz/FNA-WASM-Build/releases/download/$(STATICS_RELEASE)/FNA3D.a -O statics/FNA3D.a
	wget https://github.com/r58Playz/FNA-WASM-Build/releases/download/$(STATICS_RELEASE)/libmojoshader.a -O statics/libmojoshader.a
	wget https://github.com/r58Playz/FNA-WASM-Build/releases/download/$(STATICS_RELEASE)/SDL3.a -O statics/SDL3.a
	wget https://github.com/r58Playz/FNA-WASM-Build/releases/download/$(STATICS_RELEASE)/liba.o -O statics/liba.o
	wget https://github.com/r58Playz/FNA-WASM-Build/releases/download/$(STATICS_RELEASE)/hot_reload_detour.o -O statics/hot_reload_detour.o
	wget https://github.com/r58Playz/FNA-WASM-Build/releases/download/$(STATICS_RELEASE)/dotnet.zip -O statics/dotnet.zip
	wget https://github.com/r58Playz/FNA-WASM-Build/releases/download/$(STATICS_RELEASE)/libcrypto.a -O statics/libcrypto.a

# --- Clone repositories ---
SteamKit2.WASM:
	git clone https://github.com/srihaasmoturi-oss/SteamKit2.WASM.git --recursive
	rm -rf SteamKit2.WASM/protobuf-net

FNA:
	git clone https://github.com/FNA-XNA/FNA --recursive -b 25.02
	cd FNA && git apply ../FNA.patch

NLua:
	git clone https://github.com/NLua/NLua --recursive
	cd NLua && git checkout 9dc76edd0782d484c54433fdfa3a5097f45a379a && git apply ../nlua.patch

MonoMod:
	git clone https://github.com/r58Playz/MonoMod --recursive

# --- Clean targets ---
dotnetclean:
	rm -rvf {loader,patcher,corefier,Steamworks}/{bin,obj} frontend/public/_framework nuget || true

clean: dotnetclean
	rm -rvf statics MonoMod NLua FNA SteamKit2.WASM || true

# --- Dependencies ---
deps: statics FNA MonoMod NLua SteamKit2.WASM

# --- Build ---
build: deps
	pnpm i
	rm -rf frontend/public/_framework loader/bin/Release/net9.0/publish/wwwroot/_framework || true

	# Restore & publish loader using NuGet packages
	NUGET_PACKAGES="$(shell realpath .)/nuget" $(DOTNET_CMD) restore loader $(DOTNETFLAGS)
	bash replaceruntime.sh
	NUGET_PACKAGES="$(shell realpath .)/nuget" $(DOTNET_CMD) publish loader -c Release $(DOTNETFLAGS)

	cp -r loader/bin/Release/net9.0/publish/wwwroot/_framework frontend/public/

	# Apply runtime JS tweaks for WASM (if needed)
	sed -i 's/var offscreenCanvases \?= \?{};/var offscreenCanvases={};if(globalThis.window\&\&!window.TRANSFERRED_CANVAS){transferredCanvasNames=[".canvas"];window.TRANSFERRED_CANVAS=true;}/' frontend/public/_framework/dotnet.native.*.js
	sed -i 's/this.appendULeb(32768)/this.appendULeb(65535)/' frontend/public/_framework/dotnet.runtime.*.js
	sed -i 's/return runEmAsmFunction(code, sigPtr, argbuf);/return runMainThreadEmAsm(code, sigPtr, argbuf, 1);/' frontend/public/_framework/dotnet.native.*.js

# --- Serve & publish ---
serve: build
	pnpm dev

publish: build
	pnpm build

.PHONY: clean build serve publish deps statics
