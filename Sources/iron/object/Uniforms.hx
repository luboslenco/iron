package iron.object;

import kha.graphics4.Graphics;
import kha.graphics4.ConstantLocation;
import kha.graphics4.TextureAddressing;
import kha.graphics4.TextureFilter;
import kha.graphics4.MipMapFilter;
import iron.Scene;
import iron.math.Vec4;
import iron.math.Quat;
import iron.math.Mat4;
import iron.data.MeshData;
import iron.data.LampData;
import iron.data.MaterialData;
import iron.data.ShaderData;
import iron.data.SceneFormat;
import iron.data.RenderPath;

// Structure for setting shader uniforms
class Uniforms {

	// static var biasMat = new Mat4(
	// 	0.5, 0.0, 0.0, 0.0,
	// 	0.0, 0.5, 0.0, 0.0,
	// 	0.0, 0.0, 0.5, 0.0,
	// 	0.5, 0.5, 0.5, 1.0);
	public static var helpMat = Mat4.identity();
	public static var helpMat2 = Mat4.identity();
	public static var helpVec = new Vec4();
	public static var helpVec2 = new Vec4();
	public static var helpQuat = new Quat(); // Keep at identity

	public static var externalTextureLink:String->kha.Image = null;
	public static var externalVec3Link:String->Vec4 = null;
	public static var externalFloatLink:String->Float = null;

	public static function setConstants(g:Graphics, context:ShaderContext, object:Object, camera:CameraObject, lamp:LampObject, bindParams:Array<String>) {

		for (i in 0...context.raw.constants.length) {
			var c = context.raw.constants[i];
			setConstant(g, object, camera, lamp, context.constants[i], c);
		}

		if (bindParams != null) { // Bind targets
			for (i in 0...Std.int(bindParams.length / 2)) {
				var pos = i * 2; // bind params = [texture, samplerID]
				var rtID = bindParams[pos];
				
				var attachDepth = false; // Attach texture depth if '_' is prepended
				var char = rtID.charAt(0);
				if (char == "_") attachDepth = true;
				if (attachDepth) rtID = rtID.substr(1);
				
				var samplerID = bindParams[pos + 1];
				var pathdata = camera.data.pathdata;
				var rt = attachDepth ? pathdata.depthToRenderTarget.get(rtID) : pathdata.renderTargets.get(rtID);
				var tus = context.raw.texture_units;

				// Ping-pong
				if (rt.pong != null && !rt.pongState) rt = rt.pong;

				for (j in 0...tus.length) { // Set texture
					if (samplerID == tus[j].name) {						
						if (tus[j].is_image != null && tus[j].is_image) g.setImageTexture(context.textureUnits[j], rt.image); // image2D
						else if (attachDepth) g.setTextureDepth(context.textureUnits[j], rt.image); // sampler2D
						else g.setTexture(context.textureUnits[j], rt.image); // sampler2D

						// No filtering when sampling render targets
						if (tus[j].params_set == null) {
							tus[j].params_set = true;
							g.setTextureParameters(context.textureUnits[j], TextureAddressing.Clamp, TextureAddressing.Clamp, TextureFilter.PointFilter, TextureFilter.PointFilter, MipMapFilter.NoMipFilter);
						}
					}
				}
			}
		}
		
		// Texture links
		for (j in 0...context.raw.texture_units.length) {
			var tulink = context.raw.texture_units[j].link;
			if (tulink == null) continue;
			var tuid = context.raw.texture_units[j].name;

			if (tulink == "_envmapRadiance") {
				g.setTexture(context.textureUnits[j], Scene.active.world.getGlobalProbe().radiance);
				g.setTextureParameters(context.textureUnits[j], TextureAddressing.Repeat, TextureAddressing.Repeat, TextureFilter.LinearFilter, TextureFilter.LinearFilter, MipMapFilter.LinearMipFilter);
			}
			else if (tulink == "_envmapBrdf") {
				g.setTexture(context.textureUnits[j], Scene.active.world.brdf);
			}
			else if (tulink == "_noise8") {
				g.setTexture(context.textureUnits[j], Scene.active.embedded.get('noise8.png'));
				g.setTextureParameters(context.textureUnits[j], TextureAddressing.Repeat, TextureAddressing.Repeat, TextureFilter.LinearFilter, TextureFilter.LinearFilter, MipMapFilter.NoMipFilter);
			}
			else if (tulink == "_noise64") {
				g.setTexture(context.textureUnits[j], Scene.active.embedded.get('noise64.png'));
				g.setTextureParameters(context.textureUnits[j], TextureAddressing.Repeat, TextureAddressing.Repeat, TextureFilter.LinearFilter, TextureFilter.LinearFilter, MipMapFilter.NoMipFilter);
			}
			else if (tulink == "_noise256") {
				g.setTexture(context.textureUnits[j], Scene.active.embedded.get('noise256.png'));
				g.setTextureParameters(context.textureUnits[j], TextureAddressing.Repeat, TextureAddressing.Repeat, TextureFilter.LinearFilter, TextureFilter.LinearFilter, MipMapFilter.NoMipFilter);
			}
			else if (tulink == "_lampColorTexture") {
				if (lamp != null) {
					g.setTexture(context.textureUnits[j], lamp.data.colorTexture);
					g.setTextureParameters(context.textureUnits[j], TextureAddressing.Repeat, TextureAddressing.Repeat, TextureFilter.LinearFilter, TextureFilter.LinearFilter, MipMapFilter.NoMipFilter);
				}
			}
			// External
			else if (externalTextureLink != null) {
				var image = externalTextureLink(tulink);
				if (image != null) {
					g.setTexture(context.textureUnits[j], image);
					// g.setTextureParameters(context.textureUnits[j], TextureAddressing.Clamp, TextureAddressing.Clamp, TextureFilter.PointFilter, TextureFilter.PointFilter, MipMapFilter.NoMipFilter);
				}
			}
		}
	}

	static function setConstant(g:Graphics, object:Object, camera:CameraObject, lamp:LampObject,
								location:ConstantLocation, c:TShaderConstant) {
		if (c.link == null) return;

		if (c.type == "mat4") {
			var m:Mat4 = null;
			if (c.link == "_worldMatrix") {
				m = object.transform.matrix;
			}
			else if (c.link == "_inverseWorldMatrix") {
				helpMat.getInverse(object.transform.matrix);
				m = helpMat;
			}
			else if (c.link == "_normalMatrix") {
				helpMat.setIdentity();
				helpMat.multmat2(object.transform.matrix);
				// Non uniform anisotropic scaling, calculate normal matrix
				//if (!(object.transform.scale.x == object.transform.scale.y && object.transform.scale.x == object.transform.scale.z)) {
					helpMat.getInverse(helpMat);
					helpMat.transpose3x3();
				//}
				m = helpMat;
			}
			else if (c.link == "_viewNormalMatrix") {
				helpMat.setIdentity();
				helpMat.multmat2(object.transform.matrix);
				helpMat.multmat2(camera.V); // View space
				helpMat.getInverse(helpMat);
				helpMat.transpose3x3();
				m = helpMat;
			}
			else if (c.link == "_viewMatrix") {
				m = camera.V;
			}
			else if (c.link == "_transposeInverseViewMatrix") {
				helpMat.setIdentity();
				helpMat.multmat2(camera.V);
				helpMat.getInverse(helpMat);
				helpMat.transpose();
				m = helpMat;
			}
			else if (c.link == "_inverseViewMatrix") {
				helpMat.getInverse(camera.V);
				m = helpMat;
			}
			else if (c.link == "_transposeViewMatrix") {
				helpMat.setIdentity();
				helpMat.multmat2(camera.V);
				helpMat.transpose3x3();
				m = helpMat;
			}
			else if (c.link == "_projectionMatrix") {
				m = camera.P;
			}
			else if (c.link == "_inverseProjectionMatrix") {
				helpMat.getInverse(camera.P);
				m = helpMat;
			}
			else if (c.link == "_inverseViewProjectionMatrix") {
				helpMat.setIdentity();
				helpMat.multmat2(camera.V);
				helpMat.multmat2(camera.P);
				helpMat.getInverse(helpMat);
				m = helpMat;
			}
			else if (c.link == "_worldViewProjectionMatrix") {
				helpMat.setIdentity();
				helpMat.multmat2(object.transform.matrix);
				helpMat.multmat2(camera.V);
				helpMat.multmat2(camera.P);
				m = helpMat;
			}
			else if (c.link == "_worldViewMatrix") {
				helpMat.setIdentity();
				helpMat.multmat2(object.transform.matrix);
				helpMat.multmat2(camera.V);
				m = helpMat;
			}
			else if (c.link == "_viewProjectionMatrix") {
				helpMat.setIdentity();
				helpMat.multmat2(camera.V);
				helpMat.multmat2(camera.P);
				m = helpMat;
			}
			else if (c.link == "_prevViewProjectionMatrix") {
				helpMat.setIdentity();
				helpMat.multmat2(camera.prevV);
				helpMat.multmat2(camera.P);
				m = helpMat;
			}
#if arm_veloc
			else if (c.link == "_prevWorldViewProjectionMatrix") {
				helpMat.setIdentity();
				helpMat.multmat2(cast(object, MeshObject).prevMatrix);
				helpMat.multmat2(camera.prevV);
				// helpMat.multmat2(camera.prevP);
				helpMat.multmat2(camera.P);
				m = helpMat;
			}
#end
			else if (c.link == "_lampWorldViewProjectionMatrix") {
				if (lamp != null) {
					helpMat.setIdentity();
					if (object != null) helpMat.multmat2(object.transform.matrix); // object is null for DrawQuad
					helpMat.multmat2(lamp.V);
					helpMat.multmat2(lamp.data.P);
					m = helpMat;
				}
			}
			else if (c.link == "_lampVolumeWorldViewProjectionMatrix") {
				if (lamp != null) {
					var tr = lamp.transform;
					helpVec.set(tr.absx(), tr.absy(), tr.absz());
					helpVec2.set(lamp.data.raw.far_plane, lamp.data.raw.far_plane, lamp.data.raw.far_plane);
					helpMat.compose(helpVec, helpQuat, helpVec2);
					helpMat.multmat2(camera.V);
					helpMat.multmat2(camera.P);
					m = helpMat;
				}
			}
			else if (c.link == "_biasLampWorldViewProjectionMatrix") {
				if (lamp != null)  {
					helpMat.setIdentity();
					if (object != null) helpMat.multmat2(object.transform.matrix); // object is null for DrawQuad
					helpMat.multmat2(lamp.V);
					helpMat.multmat2(lamp.data.P);
					// helpMat.multmat2(biasMat);
					m = helpMat;
				}
			}
			else if (c.link == "_skydomeMatrix") {
				var tr = camera.transform;
				// helpVec.set(tr.absx(), tr.absy(), tr.absz() + 3.0); // Envtex
				helpVec.set(tr.absx(), tr.absy(), tr.absz() - 3.5); // Sky
				var bounds = camera.farPlane * 0.95;
				helpVec2.set(bounds, bounds, bounds);
				helpMat.compose(helpVec, helpQuat, helpVec2);
				helpMat.multmat2(camera.V);
				helpMat.multmat2(camera.P);
				m = helpMat;
			}
			else if (c.link == "_lampViewMatrix") {
				if (lamp != null) m = lamp.V;
			}
			else if (c.link == "_lampProjectionMatrix") {
				if (lamp != null) m = lamp.data.P;
			}
#if arm_vr
			else if (c.link == "_undistortionMatrix") {
				m = iron.system.VR.getUndistortionMatrix();
			}
#end
			else if (c.link == "_projectionXMatrix") {
				// TODO: cache..
				var size = 150.0; //voxelGridWorldSize;
			    var matP = Mat4.orthogonal(-size * 0.5, size * 0.5, -size * 0.5, size * 0.5, size * 0.5, size * 1.5);
			    var matLook = Mat4.lookAt(new Vec4(size, 0, 0), new Vec4(0, 0, 0), new Vec4(0, 1, 0));
			    matLook.multmat2(matP);
			    m = matLook;
			}
			else if (c.link == "_projectionYMatrix") {
				var size = 150.0;
			    var matP = Mat4.orthogonal(-size * 0.5, size * 0.5, -size * 0.5, size * 0.5, size * 0.5, size * 1.5);
			    var matLook = Mat4.lookAt(new Vec4(0, size, 0), new Vec4(0, 0, 0), new Vec4(0, 0, -1));
			    matLook.multmat2(matP);
			    m = matLook;
			}
			else if (c.link == "_projectionZMatrix") {
				var size = 150.0;
			    var matP = Mat4.orthogonal(-size * 0.5, size * 0.5, -size * 0.5, size * 0.5, size * 0.5, size * 1.5);
			    var matLook = Mat4.lookAt(new Vec4(0, 0, size), new Vec4(0, 0, 0), new Vec4(0, 1, 0));
			    matLook.multmat2(matP);
			    m = matLook;
			}
			if (m == null) return;
			g.setMatrix(location, m.self);
		}
		else if (c.type == "vec3") {
			var v:Vec4 = null;
			if (c.link == "_lampPosition") {
				if (lamp != null) helpVec.set(lamp.transform.absx(), lamp.transform.absy(), lamp.transform.absz());
				v = helpVec;
			}
			else if (c.link == "_lampDirection") {
				if (lamp != null) helpVec = lamp.look();
				v = helpVec;
			}
			else if (c.link == "_lampColor") {
				if (lamp != null) helpVec.set(lamp.data.raw.color[0], lamp.data.raw.color[1], lamp.data.raw.color[2]);
				v = helpVec;
			}
			else if (c.link == "_lampArea0") {
				if (lamp != null && lamp.data.raw.size != null) {
					var sx = lamp.data.raw.size;
					var sy = lamp.data.raw.size_y;
					helpVec.set(-sx, sy, 0.0);
					helpVec.applymat(lamp.transform.matrix);
					v = helpVec;
				}
			}
			else if (c.link == "_lampArea1") {
				if (lamp != null && lamp.data.raw.size != null) {
					var sx = lamp.data.raw.size;
					var sy = lamp.data.raw.size_y;
					helpVec.set(sx, sy, 0.0);
					helpVec.applymat(lamp.transform.matrix);
					v = helpVec;
				}
			}
			else if (c.link == "_lampArea2") {
				if (lamp != null && lamp.data.raw.size != null) {
					var sx = lamp.data.raw.size;
					var sy = lamp.data.raw.size_y;
					helpVec.set(sx, -sy, 0.0);
					helpVec.applymat(lamp.transform.matrix);
					v = helpVec;
				}
			}
			else if (c.link == "_lampArea3") {
				if (lamp != null && lamp.data.raw.size != null) {
					var sx = lamp.data.raw.size;
					var sy = lamp.data.raw.size_y;
					helpVec.set(-sx, -sy, 0.0);
					helpVec.applymat(lamp.transform.matrix);
					v = helpVec;
				}
			}
			else if (c.link == "_cameraPosition") {
				helpVec.set(camera.transform.absx(), camera.transform.absy(), camera.transform.absz());
				v = helpVec;
			}
			else if (c.link == "_cameraLook") {
				helpVec = camera.lookAbs();
				v = helpVec;
			}
			else if (c.link == "_backgroundCol") {
				helpVec.set(camera.data.raw.clear_color[0], camera.data.raw.clear_color[1], camera.data.raw.clear_color[2]);
				v = helpVec;
			}
			else if (c.link == "_probeVolumeCenter") { // Local probes
				v = Scene.active.world.getProbeVolumeCenter(object.transform);
			}
			else if (c.link == "_probeVolumeSize") {
				v = Scene.active.world.getProbeVolumeSize(object.transform);
			}
			// External
			else if (externalVec3Link != null) {
				v = externalVec3Link(c.link);
			}
			
			if (v == null) return;
			g.setFloat3(location, v.x, v.y, v.z);
		}
		else if (c.type == "vec2") {
			var vx:Float = 0;
			var vy:Float = 0;
			if (c.link == "_vec2x") vx = 1.0;
			else if (c.link == "_vec2x2") vx = 2.0;
			else if (c.link == "_vec2y") vy = 1.0;
			else if (c.link == "_vec2y2") vy = 2.0;
			else if (c.link == "_vec2y3") vy = 3.0;
			else if (c.link == "_windowSize") {
				vx = App.w();
				vy = App.h();
			}
			else if (c.link == "_windowSizeInv") {
				vx = 1.0 / App.w();
				vy = 1.0 / App.h();
			}
			else if (c.link == "_screenSize") {
				vx = camera.renderPath.currentRenderTargetW;
				vy = camera.renderPath.currentRenderTargetH;
			}
			else if (c.link == "_screenSizeInv") {
				vx = 1.0 / camera.renderPath.currentRenderTargetW;
				vy = 1.0 / camera.renderPath.currentRenderTargetH;
			}
			else if (c.link == "_aspectRatio") {
				vx = camera.renderPath.currentRenderTargetH / camera.renderPath.currentRenderTargetW;
				vy = camera.renderPath.currentRenderTargetW / camera.renderPath.currentRenderTargetH;
				vx = vx > 1.0 ? 1.0 : vx;
				vy = vy > 1.0 ? 1.0 : vy;
			}
			else if (c.link == "_cameraPlane") {
				vx = camera.data.raw.near_plane;
				vy = camera.data.raw.far_plane;
			}
			g.setFloat2(location, vx, vy);
		}
		else if (c.type == "float") {
			var f = 0.0;
			if (c.link == "_time") {
				f = kha.Scheduler.time();
			}
			else if (c.link == "_deltaTime") {
				f = iron.system.Time.delta;
			}
			else if (c.link == "_lampRadius") {
				f = lamp == null ? 0.0 : lamp.data.raw.far_plane;
			}
			else if (c.link == "_lampStrength") {
				f = lamp == null ? 0.0 : lamp.data.raw.strength;
			}
			else if (c.link == "_lampShadowsBias") {
				f = lamp == null ? 0.0 : lamp.data.raw.shadows_bias;
			}
			else if (c.link == "_lampPlaneNear") {
				f = lamp == null ? 0.0 : lamp.data.raw.near_plane;
			}
			else if (c.link == "_lampPlaneFar") {
				f = lamp == null ? 0.0 : lamp.data.raw.far_plane;
			}
			else if (c.link == "_lampSize") {
				if (lamp != null && lamp.data.raw.lamp_size != null) f = lamp.data.raw.lamp_size;
			}
			else if (c.link == "_lampSizeUV") {
				if (lamp != null && lamp.data.raw.lamp_size != null) f = lamp.data.raw.lamp_size / lamp.data.raw.fov;
			}
			else if (c.link == "_spotlampCutoff") {
				f = lamp == null ? 0.0 : lamp.data.raw.spot_size;
			}
			else if (c.link == "_spotlampExponent") {
				f = lamp == null ? 0.0 : lamp.data.raw.spot_blend;
			}
			else if (c.link == "_envmapStrength") {
				f = Scene.active.world.getGlobalProbe().raw.strength;
			}
			else if (c.link == "_probeStrength") {
				f = Scene.active.world.getProbeStrength(object.transform);
			}
			else if (c.link == "_probeBlending") {
				f = Scene.active.world.getProbeBlending(object.transform);
			}
			else if (c.link == "_aspectRatioF") {
				f = camera.renderPath.currentRenderTargetW / camera.renderPath.currentRenderTargetH;
			}
#if arm_vr
			else if (c.link == "_maxRadiusSq") {
				f = iron.system.VR.getMaxRadiusSq();
			}
#end
			// External
			else if (externalFloatLink != null) {
				f = externalFloatLink(c.link);
			}
			g.setFloat(location, f);
		}
		else if (c.type == "floats") {
			var fa:haxe.ds.Vector<kha.FastFloat> = null;
			if (c.link == "_skinBones") {
				fa = cast(object, MeshObject).animation.skinBuffer;
			}
			else if (c.link == "_envmapIrradiance") {
				// fa = Scene.active.world.getGlobalProbe().irradiance;
				fa = Scene.active.world.getSHIrradiance();
			}
			g.setFloats(location, fa);
		}
		else if (c.type == "int") {
			var i = 0;
			if (c.link == "_uid") {
				i = object.uid;
			}
			if (c.link == "_lampType") {
				i = lamp == null ? 0 : LampData.typeToInt(lamp.data.raw.type);
			}
			else if (c.link == "_lampIndex") {
				i = camera.renderPath.currentLampIndex;
			}
			else if (c.link == "_envmapNumMipmaps") {
				i = Scene.active.world.getGlobalProbe().raw.radiance_mipmaps + 1; // Include basecolor
			}
			else if (c.link == "_probeID") { // Local probes
				i = Scene.active.world.getProbeID(object.transform);
			}
			g.setInt(location, i);
		}
	}

	public static function setMaterialConstants(g:Graphics, context:ShaderContext, materialContext:MaterialContext) {
		if (materialContext.raw.bind_constants != null) {
			for (i in 0...materialContext.raw.bind_constants.length) {
				var matc = materialContext.raw.bind_constants[i];
				// TODO: cache
				var pos = -1;
				for (i in 0...context.raw.constants.length) {
					if (context.raw.constants[i].name == matc.name) {
						pos = i;
						break;
					}
				}
				if (pos == -1) continue;
				var c = context.raw.constants[pos];
				
				setMaterialConstant(g, context.constants[pos], c, matc);
			}
		}

		if (materialContext.textures != null) {
			for (i in 0...materialContext.textures.length) {
				var mname = materialContext.raw.bind_textures[i].name;

				// TODO: cache
				for (j in 0...context.textureUnits.length) {
					var sname = context.raw.texture_units[j].name;
					if (mname == sname) {
						g.setTexture(context.textureUnits[j], materialContext.textures[i]);
						// After texture sampler have been assigned, set texture parameters
						materialContext.setTextureParameters(g, i, context, j);
						break;
					}
				}
			}
		}
	}

	static function setMaterialConstant(g:Graphics, location:ConstantLocation, c:TShaderConstant, matc:TBindConstant) {
		switch (c.type) {
		case "vec4": g.setFloat4(location, matc.vec4[0], matc.vec4[1], matc.vec4[2], matc.vec4[3]);
		case "vec3": g.setFloat3(location, matc.vec3[0], matc.vec3[1], matc.vec3[2]);
		case "vec2": g.setFloat2(location, matc.vec2[0], matc.vec2[1]);
		case "float": g.setFloat(location, matc.float);
		case "bool": g.setBool(location, matc.bool);
		}
	}
}