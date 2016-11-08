package iron.object;

import kha.graphics4.Graphics;
import iron.Scene;
import iron.math.Mat4;
import iron.math.Vec4;
import iron.math.Quat;
import iron.data.CameraData;
import iron.data.RenderPath;

class CameraObject extends Object {

	public var data:CameraData;
	public var renderPath:RenderPath;

	public var P:Mat4; // Matrices
// #if arm_veloc
	// public var prevP:Mat4;
// #end
#if arm_taa
	public var noJitterP:Mat4;
#end
	public var V:Mat4;
	public var prevV:Mat4 = null;
	public var VP:Mat4;
	public var frustumPlanes:Array<FrustumPlane> = null;
	public var nearPlane:Float;
	public var farPlane:Float;

	public function new(data:CameraData) {
		super();

		this.data = data;

		renderPath = new RenderPath(this);

		nearPlane = data.raw.near_plane;
		farPlane = data.raw.far_plane;

		var fov = data.raw.fov;

		if (data.raw.type == "perspective") {
			var w:Float = iron.App.w();
			var h:Float = iron.App.h();
#if arm_vr
			w /= 2.0; // Split per eye
#end
			P = Mat4.perspective(fov, w / h, nearPlane, farPlane);
		}
		else if (data.raw.type == "orthographic") {
			P = Mat4.orthogonal(-10, 10, -6, 6, -farPlane, farPlane);
		}

// #if arm_veloc
		// prevP = Mat4.identity();
		// prevP.setFrom(P);
// #end

#if arm_taa
		noJitterP = Mat4.identity();
		noJitterP.setFrom(P);
#end

		V = Mat4.identity();
		VP = Mat4.identity();

		if (data.raw.frustum_culling) {
			frustumPlanes = [];
			for (i in 0...6) frustumPlanes.push(new FrustumPlane());
		}

		Scene.active.cameras.push(this);
	}

	public override function remove() {
		Scene.active.cameras.remove(this);
		super.remove();
	}

	public function renderFrame(g:Graphics, root:Object, lamps:Array<LampObject>) {
#if arm_taa
		projectionJitter();
#end
		buildMatrix(); // TODO: only when dirty

		// First time setting up previous V, prevents first frame flicker
		if (prevV == null) {
			prevV = Mat4.identity();
			prevV.setFrom(V);
		}

		renderPath.renderFrame(g, root, lamps);
	
		prevV.setFrom(V);
// #if (arm_veloc && arm_taa)
		// prevP.setFrom(P);
// #end
	}

#if arm_taa
	var frame = 0;
	function projectionJitter() {
		var w = renderPath.currentRenderTargetW;
		var h = renderPath.currentRenderTargetH;
		P.setFrom(noJitterP);
		var x = 0.0;
		var y = 0.0;
		// Alternate only 2 frames for now
		if (frame % 2 == 0) { x = 0.25; y = 0.25; }
		else if (frame % 2 == 1) { x = -0.25; y = -0.25; }
		P._20 += x / w;
		P._21 += y / h;
		frame++;
	}
#end

	public function buildMatrix() {
		transform.buildMatrix();
		V.getInverse(transform.matrix);

		if (data.raw.frustum_culling) {
			VP.multmats(P, V);
			buildViewFrustum(VP, frustumPlanes);
		}
	}

	public static function buildViewFrustum(VP:Mat4, frustumPlanes:Array<FrustumPlane>) {
		// Left plane
		frustumPlanes[0].setComponents(
			VP._03 + VP._00,
			VP._13 + VP._10,
			VP._23 + VP._20,
			VP._33 + VP._30
		);
	 
		// Right plane
		frustumPlanes[1].setComponents(
			VP._03 - VP._00,
			VP._13 - VP._10,
			VP._23 - VP._20,
			VP._33 - VP._30
		);
	 
		// Top plane
		frustumPlanes[2].setComponents(
			VP._03 - VP._01,
			VP._13 - VP._11,
			VP._23 - VP._21,
			VP._33 - VP._31
		);
	 
		// Bottom plane
		frustumPlanes[3].setComponents(
			VP._03 + VP._01,
			VP._13 + VP._11,
			VP._23 + VP._21,
			VP._33 + VP._31
		);
	 
		// Near plane
		frustumPlanes[4].setComponents(
			VP._02,
			VP._12,
			VP._22,
			VP._32
		);
	 
		// Far plane
		frustumPlanes[5].setComponents(
			VP._03 - VP._02,
			VP._13 - VP._12,
			VP._23 - VP._22,
			VP._33 - VP._32
		);
	 
		// Normalize planes
		for (plane in frustumPlanes) plane.normalize();
	}

	static var sphereCenter = new Vec4();
	public static function sphereInFrustum(frustumPlanes:Array<FrustumPlane>, t:Transform, radiusScale = 1.0, offsetX = 0.0, offsetY = 0.0, offsetZ = 0.0):Bool {
		// Use scale when radius is changing
		var radius = t.radius * radiusScale;
		for (plane in frustumPlanes) {	
			sphereCenter.set(t.absx() + offsetX, t.absy() + offsetY, t.absz() + offsetZ);
			// Outside the frustum
			if (plane.distanceToSphere(sphereCenter, radius) + radius * 2 < 0) {
				return false;
			}
		}
		return true;
	}

	public function rotate(axis:Vec4, f:Float) {
		var q = new Quat();
		q.fromAxisAngle(axis, f);
		transform.rot.multquats(q, transform.rot);
		transform.dirty = true;
		buildMatrix();
	}

	public function move(axis:Vec4, f:Float) {
		axis.mult(f);
		transform.loc.add(axis);
		transform.dirty = true;
		buildMatrix();
	}

	public inline function right():Vec4 { return new Vec4(transform.local._00, transform.local._01, transform.local._02); }
	public inline function up():Vec4 { return new Vec4(transform.local._10, transform.local._11, transform.local._12); }
	public inline function look():Vec4 { return new Vec4(-transform.local._20, -transform.local._21, -transform.local._22); }
	public inline function rightAbs():Vec4 { return new Vec4(transform.matrix._00, transform.matrix._01, transform.matrix._02); }
	public inline function upAbs():Vec4 { return new Vec4(transform.matrix._10, transform.matrix._11, transform.matrix._12); }
	public inline function lookAbs():Vec4 { return new Vec4(-transform.matrix._20, -transform.matrix._21, -transform.matrix._22); }
}

class FrustumPlane {
	public var normal = new Vec4(1.0, 0.0, 0.0);
	public var constant = 0.0;

	public function new() { }

	public function normalize() {
		var inverseNormalLength = 1.0 / normal.length();
		normal.mult(inverseNormalLength);
		constant *= inverseNormalLength;
	}
	
	public function distanceToSphere(sphereCenter:Vec4, sphereRadius:Float):Float {
		return (normal.dot(sphereCenter) + constant) - sphereRadius;
	}

	public inline function setComponents(x:Float, y:Float, z:Float, w:Float) {
		normal.set(x, y, z);
		constant = w;
	}
}