package fox.trait;

import fox.core.Object;
import fox.core.Trait;
import fox.sys.importer.DaeData;
import fox.sys.importer.Animation;
import fox.sys.importer.AnimationClip;
import fox.sys.material.Material;
import fox.sys.material.TextureMaterial;
import fox.sys.mesh.SkinnedMesh;
import fox.sys.Assets;
import fox.sys.geometry.Geometry;
import fox.sys.mesh.Mesh;
import fox.trait.Renderer;
import fox.trait.MeshRenderer;
import fox.trait.SkinnedMeshRenderer;
import fox.trait.SceneRenderer;
import fox.trait.Transform;

typedef TGameData = {
	materials:Array<TGameMaterial>,
	scene:String,
	orient:Int,
	packageName:String,
	gravity:Array<Float>,
	clear:Array<Float>,
	fogColor:Array<Float>,
	fogDensity:Float,
	shadowMapping:Int,
	shadowMapSize:Int,
}

typedef TGameMaterial = {
	name:String,
	nodes:Array<TGameNode>,
}

typedef TGameNode = {
	name:String,
	inputs:Array<TGameInput>,
	outputs:Array<TGameOutput>,
}

typedef TGameInput = {
	name:String,
	value:Dynamic,
}

typedef TGameOutput = {
	name:String,
	value:Dynamic,
}

class DaeScene extends Trait {

	var daeData:DaeData;
	var gameData:TGameData;

	var nodeObjectMap:Map<DaeNode, Object>;
	var transformControllerMap:Map<Transform, DaeController>;
	var materialMap:Map<DaeMaterial, Material>;
	
	var jointTransforms:Array<Transform> = [];
	var jointNodes:Array<DaeNode> = [];
	var skinnedRenderers:Array<SkinnedMeshRenderer> = [];

	public function new(data:String) {

		super();

		daeData = new DaeData(data);

		nodeObjectMap = new Map<DaeNode, Object>();
		transformControllerMap = new Map<Transform, DaeController>();
		materialMap = new Map<DaeMaterial, Material>();
	}

	public function getNode(name:String):DaeNode {
		var node:DaeNode = null;

		daeData.scene.traverse(function(n:DaeNode) {
			if (n.name == name) {
				node = n;
				return;
			}
		});

		return node;
	}

	public function createNode(node:DaeNode):Object {
		var parentObject = node.parent == null ? parent : (nodeObjectMap.exists(node.parent) ? nodeObjectMap.get(node.parent) : parent);
		var child = new Object();
		child.name = node.name;
		child.name = StringTools.replace(child.name, ".", "_");

		if (node.type == "joint") {
			child.transform.name = child.name;
			jointTransforms.push(child.transform);
			jointNodes.push(node);
		}

		child.transform.pos.set(node.position.x, node.position.y, node.position.z);
		child.transform.scale.set(node.scale.x, node.scale.y, node.scale.z);
		child.transform.rot.set(node.rotation.x, node.rotation.y, node.rotation.z, node.rotation.w);

		nodeObjectMap.set(node, child);

		for (i in 0...node.instances.length) {
			var renderer:Renderer = null;
			var daeInst:DaeInstance = node.instances[i];
			var daeMat:DaeMaterial = null;				
			var daeGeom:DaeGeometry = null;
			var daeGeomTarget = "";
			var daeContr:DaeController = null;

			if (daeInst.type == "geometry") {
				daeGeomTarget = daeInst.target;
			}
			else if (daeInst.type == "controller") {
				daeContr = daeData.getControllerById(daeInst.target);						
				if (daeContr != null) {
					transformControllerMap.set(child.transform, daeContr);
					daeGeomTarget = daeContr.source;
				}	
			}

			if (daeInst.type == "geometry" || daeInst.type == "controller") {
				var daeGeom = daeData.getGeometryById(daeGeomTarget);

				for (i in 0...daeGeom.mesh.primitives.length) {
					var daePrim = daeGeom.mesh.primitives[i];
					renderer = createRenderer(child, daePrim, daeContr);
					if (daeContr != null && renderer != null) skinnedRenderers.push(cast renderer);
				}

				// Create object traits
				createTraits(child, node.instances[i].materials);
			}

			parentObject.addChild(child);
		}

		return child;
	}

	override function onItemAdd() {

		if (daeData.scene == null) return;

		var scene = daeData.scene;

		// Scene renderer
		parent.addTrait(new SceneRenderer());
		parent.name = scene.name;

		// Game data reference
		gameData = Main.gameData;

		// Create scene nodes
		scene.traverse(function(node:DaeNode) {
			if (node.name.charAt(0) == "_") { // TODO: use custom tag instead
				return; // Skip hidden objects
			}

			createNode(node);
		});

		for (i in 0...skinnedRenderers.length) {
			var skinnedRen:SkinnedMeshRenderer = skinnedRenderers[i];
			
			var daeContr = transformControllerMap.exists(skinnedRen.transform) ? transformControllerMap.get(skinnedRen.transform) : null;
			if (daeContr == null) continue;
			
			skinnedRen.joints = [];
			
			for (j in 0...daeContr.joints.length) {
				for (k in 0...jointTransforms.length) {
					if (jointTransforms[k].name == daeContr.joints[j]) {
						skinnedRen.joints.push(jointTransforms[k]);		
					}
				}
			}
		}

		addAnimations(parent, jointTransforms);

		/*if (first) {
			first = false;
			var o = new Object();
			var dae = new DaeScene(Assets.getString("animation_run"));
	        o.addTrait(dae);
			daeData.addAnimations(parent, jointTransforms);
		}*/

		/*var anim:Animation = parent.getTrait(Animation);
		if (anim != null) {
			for (i in 0...anim.clips.length) {
				var clip = anim.clips[i];
				clip.wrap = AnimationClip.AnimationWrap.Loop;
				clip.name = "clip" + i;
			}

			anim.play(anim.clips[0]);
		}*/
	}
	//static var first = true;

	public function createTraits(obj:Object, mats:Array<String>) { // TODO: rename
		for (i in 0...mats.length) {
			createTrait(obj, mats[i]);
		}
	}

	public function createTrait(obj:Object, mat:String) {

		// Find materials data
		var matData:TGameMaterial = null;
		for (i in 0...gameData.materials.length) {
			var str = StringTools.replace(mat, "_", ".");
			if (str == gameData.materials[i].name) {
				matData = gameData.materials[i];
			}
		}

		// Find nodes
		var materialDatas:Array<TGameNode> = [];
		if (matData != null) {
			for (i in 0...matData.nodes.length) {
				if (matData.nodes[i].name.split(".")[0] == "Trait") {
					materialDatas.push(matData.nodes[i]);
				}
			}
		}

		// Find inputs
		var stringInputs:Array<TGameInput> = [];
		for (i in 0...materialDatas.length) {
			for (j in 0...materialDatas[i].inputs.length) {
				if (materialDatas[i].inputs[j].name == "Name") {
					stringInputs.push(materialDatas[i].inputs[j]);
				}
			}
		}

		for (stringInput in stringInputs) {

			var s:Array<String> = stringInput.value.split(":");
			var traitName = s[0];

			// Parse arguments
			var args:Dynamic = [];
			for (i in 1...s.length) {

				if (s[i] == "true") args.push(true);
				else if (s[i] == "false") args.push(false);
				else if (s[i].charAt(0) != '"') args.push(Std.parseFloat(s[i]));
				else {
					args.push(StringTools.replace(s[i], '"', ""));
				}
			}
			
			obj.addTrait(createClassInstance(traitName, args));
		}
	}

	function createClassInstance(traitName:String, args:Dynamic):Dynamic {
		// Try game package
		var cname = Type.resolveClass(gameData.packageName + "." + traitName);

		// Try fox package
		if (cname == null) cname = Type.resolveClass("fox.trait." + traitName);
		
		return Type.createInstance(cname, args);
	}

	function createRenderer(object:Object, daePrim:DaePrimitive, daeContr:DaeController):Renderer {
		
		if (daePrim.material == "") return null;
		var mat = daeData.getMaterialById(daePrim.material).name;

		// Find materials data
		var matData:TGameMaterial = null;
		for (i in 0...gameData.materials.length) {
			var str = StringTools.replace(mat, "_", ".");
			if (str == gameData.materials[i].name) {
				matData = gameData.materials[i];
			}
		}

		// Find nodes
		var materialData:TGameNode = null;
		if (matData != null) {
			for (i in 0...matData.nodes.length) {

				var matName = matData.nodes[i].name.split(".")[0];

				if (matName == "Mesh Material" || matName == "Custom Material") {
					materialData = matData.nodes[i];
					materialData.name = matName;
					break;
				}
			}
		}

		// Mesh material
		if (materialData != null && materialData.name == "Mesh Material") {
			// Find inputs
			var lightingInput:TGameOutput = null;
			var rimInput:TGameOutput = null;
			var textureInput:TGameOutput = null;
			var colorInput:TGameOutput = null;
			var castShadowInput:TGameOutput = null;
			var receiveShadowInput:TGameOutput = null;
			if (materialData != null) {
				for (i in 0...materialData.inputs.length) {
					if (materialData.inputs[i].name == "Lighting") {
						lightingInput = materialData.inputs[i];
					}
					else if (materialData.inputs[i].name == "Rim") {
						rimInput = materialData.inputs[i];
					}
					else if (materialData.inputs[i].name == "Texture") {
						textureInput = materialData.inputs[i];
					}
					else if (materialData.inputs[i].name == "Color") {
						colorInput = materialData.inputs[i];
					}
					else if (materialData.inputs[i].name == "Cast Shadow") {
						castShadowInput = materialData.inputs[i];
					}
					else if (materialData.inputs[i].name == "Receive Shadow") {
						receiveShadowInput = materialData.inputs[i];
					}
				}
			}
			else {
				return null;
			}

			var isSkinned = daeContr == null ? false : true;

			var va:Array<kha.math.Vector3> = daePrim.getTriangulatedArray("vertex");
			var na:Array<kha.math.Vector3> = daePrim.getTriangulatedArray("normal"); 
			var uva:Array<kha.math.Vector2> = daePrim.getTriangulatedArray("texcoord", 0);
			var ca:Array<kha.Color> = daePrim.getTriangulatedArray("color");
			var wa:Array<kha.math.Vector4> = null;
			var ba:Array<kha.math.Vector4> = null;

			if (isSkinned) {
				if (daeContr != null) {			
					daeContr.generateBonesAndWeights();
					
					wa = daeContr.getTriangulatedWeights(daePrim);
					ba = daeContr.getTriangulatedBones(daePrim);			
					//var bsm:kha.math.Matrix4 = daeContr.getBSM();
					
					//for (i in 0...va.length)  { va[i] = bsm.transform3x4(va[i].clone); }
					//for (i in 0...na.length)  { na[i] = bsm.transform3x3(na[i].clone); }
					//for (i in 0...mbn.length) { mbn[i] = bsm.transform3x3(mbn[i].clone); }
					//for (i in 0...mtg.length) { mtg[i] = bsm.transform3x3(mtg[i].clone); }
				}
			}

			var data:Array<Float> = [];
			var indices:Array<Int> = [];
			
			for (i in 0...va.length) {
				data.push(va[i].x); // Pos
				data.push(va[i].y);
				data.push(va[i].z);

				if (uva.length > 0) {
					data.push(uva[i].x); // TC
					data.push(uva[i].y);
				}
				else {
					data.push(0);
					data.push(0);
				}

				if (na.length > 0) {
					data.push(na[i].x); // Normal
					data.push(na[i].y);
					data.push(na[i].z);
				}
				else {
					data.push(1);
					data.push(1);
					data.push(1);
				}

				if (ca.length > 0) { // Color
					data.push(ca[i].R); // Vertex colors
					data.push(ca[i].G);
					data.push(ca[i].B);
					data.push(ca[i].A);
				}
				else {
					data.push(colorInput.value[0]);	// Material color
					data.push(colorInput.value[1]);
					data.push(colorInput.value[2]);
					data.push(colorInput.value[3]);
				}

				if (isSkinned) { // Weights and bones
					data.push(wa[i].x);
					data.push(wa[i].y);
					data.push(wa[i].z);
					data.push(wa[i].w);

					data.push(ba[i].x);
					data.push(ba[i].y);
					data.push(ba[i].z);
					data.push(ba[i].w);
				}

				indices.push(i);
			}

			var geo = new Geometry(data, indices, va, na);
			
			var tb = false;
			if (textureInput != null) tb = textureInput.value == "" ? false : true;
			var texturing = (textureInput != null && uva.length > 0) ? tb : false;
			var lighting = lightingInput != null ? lightingInput.value : true;
			var rim = rimInput != null ? rimInput.value : true;
			var castShadow = castShadowInput != null ? castShadowInput.value : false;
			var receiveShadow = receiveShadowInput != null ? receiveShadowInput.value : false;

			var shaderName = "shader";
			if (isSkinned) shaderName = "skinnedshader";

			if (!texturing) {
				Assets.addMaterial(mat, new Material(Assets.getShader(shaderName)));
			}
			else {
				Assets.addMaterial(mat, new TextureMaterial(Assets.getShader(shaderName),
															Assets.getTexture(textureInput.value)));
			}

			var mesh:Mesh = null;
			if (isSkinned) {
				mesh = new SkinnedMesh(geo, Assets.getMaterial(mat));

				if (daeContr != null) {			
					var skinnedMesh:SkinnedMesh = cast mesh;			
					skinnedMesh.weight = daeContr.getTriangulatedWeights(daePrim);
					skinnedMesh.bone = daeContr.getTriangulatedBones(daePrim);
					skinnedMesh.binds = daeContr.getBinds();
				}
			}
			else {
				mesh = new Mesh(geo, Assets.getMaterial(mat));
			}

			var renderer:MeshRenderer = null;
			if (isSkinned) renderer = new SkinnedMeshRenderer(cast mesh);
			else renderer = new MeshRenderer(mesh);
			renderer.texturing = texturing;
			renderer.lighting = lighting;
			renderer.rim = rim;
			renderer.castShadow = castShadow;
			renderer.receiveShadow = receiveShadow;
			renderer.setMat4(renderer.mvpMatrix);
			renderer.setMat4(renderer.shadowMapMatrix);
			renderer.setMat4(renderer.viewMatrix);
			if (isSkinned) {
				var skinnedRenderer:SkinnedMeshRenderer = cast renderer;
				skinnedRenderer.setMat4(skinnedRenderer.projectionMatrix);
			}
			renderer.setBool(texturing);
			renderer.setBool(lighting);
			renderer.setBool(rim);
			renderer.setBool(castShadow);
			renderer.setBool(receiveShadow);
			renderer.setTexture(fox.core.FrameRenderer.shadowMap);
			object.addTrait(renderer);
			return renderer;
		}
		// Custom material TODO: merge
		else {
			// Find inputs
			var colorInput:TGameOutput = null;
			var textureInput:TGameOutput = null;
			var shaderInput:TGameOutput = null;
			var rendererInput:TGameOutput = null;
			if (materialData != null) {
				for (i in 0...materialData.inputs.length) {
					if (materialData.inputs[i].name == "Color") {
						colorInput = materialData.inputs[i];
					}
					else if (materialData.inputs[i].name == "Texture") {
						textureInput = materialData.inputs[i];
					}
					else if (materialData.inputs[i].name == "Shader") {
						shaderInput = materialData.inputs[i];
					}
					else if (materialData.inputs[i].name == "Renderer") {
						rendererInput = materialData.inputs[i];
					}
				}
			}
			else {
				return null;
			}

			var va:Array<kha.math.Vector3> = daePrim.getTriangulatedArray("vertex");
			var na:Array<kha.math.Vector3> = daePrim.getTriangulatedArray("normal"); 
			var uva:Array<kha.math.Vector2> = daePrim.getTriangulatedArray("texcoord", 0);
			var ca:Array<kha.Color> = daePrim.getTriangulatedArray("color");

			var data:Array<Float> = [];
			var indices:Array<Int> = [];
			
			for (i in 0...va.length) {
				data.push(va[i].x); // Pos
				data.push(va[i].y);
				data.push(va[i].z);

				if (uva.length > 0) {
					data.push(uva[i].x); // TC
					data.push(uva[i].y);
				}
				else {
					data.push(0);
					data.push(0);
				}

				if (na.length > 0) {
					data.push(na[i].x); // Normal
					data.push(na[i].y);
					data.push(na[i].z);
				}
				else {
					data.push(1);
					data.push(1);
					data.push(1);
				}

				if (ca.length > 0) { // Color
					data.push(ca[i].R); // Vertex colors
					data.push(ca[i].G);
					data.push(ca[i].B);
					data.push(ca[i].A);
				}
				else {
					data.push(colorInput.value[0]);	// Material color
					data.push(colorInput.value[1]);
					data.push(colorInput.value[2]);
					data.push(colorInput.value[3]);
				}

				indices.push(i);
			}

			var geo = new Geometry(data, indices, va, na);
			
			var shaderNm = shaderInput != null ? shaderInput.value : "";
			var rendererNm = rendererInput != null ? rendererInput.value : "";
			var tb = false;
			if (textureInput != null) tb = textureInput.value == "" ? false : true;
			var texturing = (textureInput != null && uva.length > 0) ? tb : false;

			var shaderName = shaderNm;
			if (!texturing) {
				Assets.addMaterial(mat, new Material(Assets.getShader(shaderName)));
			}
			else {
				Assets.addMaterial(mat, new TextureMaterial(Assets.getShader(shaderName),
															Assets.getTexture(textureInput.value)));
			}

			var mesh:Mesh = null;
			mesh = new Mesh(geo, Assets.getMaterial(mat));

			var renderer:Dynamic = createClassInstance(rendererNm, [mesh]);
			renderer.texturing = texturing;
			renderer.initConstants();
			object.addTrait(renderer);
			return renderer;
		}
	}

	public function addAnimations(root:Object, jointTransforms:Array<Transform>) {

		if (daeData.animations.length <= 0) return;

		var anim = root.getTrait(Animation);
		if (anim == null) {
			anim = new Animation();
			root.addTrait(anim);
		}
		
		for (i in 0...daeData.animations.length) {

			var daeAnim = daeData.animations[i];
			var clip = new AnimationClip();
			clip.name = daeAnim.name;	
			
			for (j in 0...daeAnim.channels.length) {

				var channel = daeAnim.channels[j];
				var nodeName = channel.target.split("/")[0];
				nodeName = StringTools.replace(nodeName, "node-", "");
				var targetName = channel.target.split("/")[1];

				var transform:Transform = null;
				for (i in 0...jointTransforms.length) {
					if (jointTransforms[i].name == nodeName) {
						transform = jointTransforms[i];
						break;
					}
				}
				if (transform == null) continue;

				if (targetName == "matrix") {
					var positionTrack = clip.add(transform, "pos");							
					var rotationTrack = clip.add(transform, "rot");

					for (k in 0...channel.keyframes.length) {
						var keyframe = channel.keyframes[k];
						var mat = new fox.math.Mat4(keyframe.values);// fox.math.Mat4.FromArray();
						var trans = mat.getTransform();
						positionTrack.add(keyframe.time, trans[0]);
						rotationTrack.add(keyframe.time, trans[1]);
					}		
				}
			}
			
			anim.add(clip);				
		}
	}
}
