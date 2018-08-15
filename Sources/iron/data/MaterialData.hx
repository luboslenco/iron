package iron.data;

import haxe.ds.Vector;
import iron.data.SceneFormat;
import iron.data.ShaderData;
import iron.object.MeshObject;

class MaterialData extends Data {

	static var uidCounter = 0;
	public var uid:Float;
	public var name:String;
	public var raw:TMaterialData;
	public var shader:ShaderData;

	public var contexts:Array<MaterialContext> = null;

	public function new(raw:TMaterialData, filePath:String, done:MaterialData->Void) {
		super();

		uid = ++uidCounter; // Start from 1
		this.raw = raw;
		this.name = raw.name;

		var ref = raw.shader.split(":");
		var object_file = "";
		var data_ref = "";
		if (ref.length == 2) { // File reference
			object_file = ref[0];
			data_ref = ref[1];

			if (!StringTools.startsWith(object_file, "/") && filePath.indexOf("/") != -1) { // Relative path
				object_file = new haxe.io.Path(filePath).dir + "/" + object_file;
			}
		}
		else { // Local data
			object_file = filePath;
			data_ref = raw.shader;
		}
		
		Data.getShader(object_file, data_ref, raw.override_context, function(b:ShaderData) {
			shader = b;

			// Contexts have to be in the same order as in raw data for now
			contexts = [];
			// contexts = new Vector(raw.contexts.length);
			while (contexts.length < raw.contexts.length) contexts.push(null);
			var contextsLoaded = 0;

			for (i in 0...raw.contexts.length) {
				var c = raw.contexts[i];
				new MaterialContext(c, filePath, function(self:MaterialContext) {
					contexts[i] = self;
					contextsLoaded++;
					if (contextsLoaded == raw.contexts.length) done(this);
				});
			}
		});
	}

	public static function parse(file:String, name:String, done:MaterialData->Void) {
		Data.getSceneRaw(file, function(format:TSceneFormat) {
			var raw:TMaterialData = Data.getMaterialRawByName(format.material_datas, name);
			if (raw == null) {
				trace('Material data "$name" not found!');
				done(null);
			}
			new MaterialData(raw, file, done);
		});
	}

	public function getContext(name:String):MaterialContext {
		for (c in contexts) {
			// 'mesh' will fetch both 'mesh' and 'meshheight' contexts
			if (c.raw.name.substr(0, name.length) == name) return c;
		}
		return null;
	}

	public function toString():String { return "Material " + name; }
}

class MaterialContext {
	public var raw:TMaterialContext;
	public var filePath:String;
	public var textures:Vector<kha.Image> = null;
	public var id = 0;
	static var num = 0;

	public function new(raw:TMaterialContext, filePath:String, done:MaterialContext->Void) {
		this.raw = raw;
		this.filePath = filePath;
		id = num++;

		if (raw.bind_textures != null && raw.bind_textures.length > 0) {
			
			textures = new Vector(raw.bind_textures.length);
			var texturesLoaded = 0;

			for (i in 0...raw.bind_textures.length) {
				var tex = raw.bind_textures[i];
				// TODO: make sure to store in the same order as shader texture units array

				if (tex.file == '') { // Empty texture
					texturesLoaded++;
					if (texturesLoaded == raw.bind_textures.length) done(this);
					continue;
				}

				// Get path relative to material file
				var texPath = tex.file;
				var subdir = haxe.io.Path.directory(this.filePath);
				if (subdir != "") {
					texPath = subdir + "/" + tex.file;
				}

				iron.data.Data.getImage(texPath, function(image:kha.Image) {
					textures[i] = image;
					texturesLoaded++;

					// Set mipmaps
					if (tex.mipmaps != null) {
						var mipmaps:Array<kha.Image> = [];
						while (mipmaps.length < tex.mipmaps.length) mipmaps.push(null);
						var mipmapsLoaded = 0;

						for (j in 0...tex.mipmaps.length) {
							var name = tex.mipmaps[j];

							iron.data.Data.getImage(name, function(mipimg:kha.Image) {
								mipmaps[j] = mipimg;
								mipmapsLoaded++;

								if (mipmapsLoaded == tex.mipmaps.length) {
									image.setMipmaps(mipmaps);
									tex.mipmaps = null;
									tex.generate_mipmaps = false;

									if (texturesLoaded == raw.bind_textures.length) done(this);
								}
							});
						}
					}
					else if (tex.generate_mipmaps == true && image != null) {
						image.generateMipmaps(1000);
						tex.mipmaps = null;
						tex.generate_mipmaps = false;

						if (texturesLoaded == raw.bind_textures.length) done(this);
					}
					else if (texturesLoaded == raw.bind_textures.length) done(this);
				
				}, false, tex.format != null ? tex.format : 'RGBA32');
			}
		}
		else done(this);
	}
	
	public function setTextureParameters(g:kha.graphics4.Graphics, textureIndex:Int, context:ShaderContext, unitIndex:Int) {
		// This function is called by MeshObject for samplers set using material context
		if (!context.paramsSet[unitIndex]) {
			context.setTextureParameters(g, unitIndex, raw.bind_textures[textureIndex]);
			#if (kha_opengl || kha_webgl) // TODO: need to re-set params for direct3d11
			context.paramsSet[unitIndex] = true;
			#end
		}
	}
}
