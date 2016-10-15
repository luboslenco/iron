package iron.math;

class Vec4 {

	public var x:Float;
	public var y:Float;
	public var z:Float;
	public var w:Float;

	public function new(x:Float = 0.0, y:Float = 0.0, z:Float = 0.0, w:Float = 1.0) {
		this.x = x;
		this.y = y;
		this.z = z;
		this.w = w;
	}

	public function cross(v:Vec4):Vec4 {
		var x2 = y * v.z - z * v.y;
		var y2 = z * v.x - x * v.z;
		var z2 = x * v.y - y * v.x;
		x = x2;
		y = y2;
		z = z2;
		return this;
	}

	public function crossvecs(a:Vec4, b:Vec4):Vec4 {
		var x2 = a.y * b.z - a.z * b.y;
		var y2 = a.z * b.x - a.x * b.z;
		var z2 = a.x * b.y - a.y * b.x;
		x = x2;
		y = y2;
		z = z2;
		return this;
	}

	public function set(x:Float, y:Float, z:Float):Vec4{
		this.x = x;
		this.y = y;
		this.z = z;
		return this;
	}

	public function add(v:Vec4):Vec4 {
		x += v.x;
		y += v.y;
		z += v.z;
		return this;
	}

	public function addf(x:Float, y:Float, z:Float):Vec4 {
		this.x += x;
		this.y += y;
		this.z += z;
		return this;
	}

	public function subvecs(a:Vec4, b:Vec4):Vec4 {
		var x2 = a.x - b.x;
		var y2 = a.y - b.y;
		var z2 = a.z - b.z;
		x = x2;
		y = y2;
		z = z2;
		return this;
	}   

	public function normalize():Vec4 {
		var n = length();
		if (n > 0.0) {
			var invN = 1.0 / n;
			this.x *= invN; this.y *= invN; this.z *= invN;
		}
		return this;
	}

	public function mult(f:Float):Vec4 {
		x *= f; y *= f; z *= f;
		return this;
	}

	public function dot(v:Vec4):Float {
		return this.x * v.x + this.y * v.y + this.z * v.z;
	}

	public function setFrom(v:Vec4):Vec4 {
		x = v.x; y = v.y; z = v.z;
		return this;
	}   

	public function clone():Vec4 {
		return new Vec4(x, y, z);
	}

	public static function lerp(v1:Vec4, v2:Vec4, t:Float) {
		var target = new Vec4();
		target.x = v2.x + (v1.x - v2.x) * t;
		target.y = v2.y + (v1.y - v2.y) * t;
		target.z = v2.z + (v1.z - v2.z) * t;
		return target;
	}

	public function applyproj(m:Mat4):Vec4 {
		var x = this.x;
		var y = this.y;
		var z = this.z;

		// Perspective divide
		var d = 1 / (m._03 * x + m._13 * y + m._23 * z + m._33);

		this.x = (m._00 * x + m._10 * y + m._20 * z + m._30) * d;
		this.y = (m._01 * x + m._11 * y + m._21 * z + m._31) * d;
		this.z = (m._02 * x + m._12 * y + m._22 * z + m._32) * d;

		return this;
	}

	public function applymat(m:Mat4):Vec4 {
		var x = this.x;
		var y = this.y;
		var z = this.z;

		this.x = (m._00 * x + m._10 * y + m._20 * z + m._30);
		this.y = (m._01 * x + m._11 * y + m._21 * z + m._31);
		this.z = (m._02 * x + m._12 * y + m._22 * z + m._32);

		return this;
	}

	public inline function length() {
		return std.Math.sqrt(x * x + y * y + z * z);
	}

	public function sub(v:Vec4):Vec4 {
		x -= v.x; y -= v.y; z -= v.z;
		return this;
	} 

	public function unproject(P:Mat4, V:Mat4):Vec4 {
		var VPInv = Mat4.identity();
		var PInv = Mat4.identity();
		var VInv = Mat4.identity();

		PInv.getInverse(P);
		VInv.getInverse(V);

		VPInv.multmats(VInv, PInv);

		return this.applyproj(VPInv);
	}

	public static inline function distance3d(v1:Vec4, v2:Vec4):Float {
		return distance3df(v1.x, v1.y, v1.z, v2.x, v2.y, v2.z);
	}

	public static inline function distance3df(v1x:Float, v1y:Float, v1z:Float, v2x:Float, v2y:Float, v2z:Float):Float {
		var vx = v1x - v2x;
		var vy = v1y - v2y;
		var vz = v1z - v2z;
		return std.Math.sqrt(vx * vx + vy * vy + vz * vz);
	}

	public function distanceTo(p:Vec4):Float {
		return std.Math.sqrt((p.x - x) * (p.x - x) + (p.y - y) * (p.y - y) + (p.z - z) * (p.z - z));
	}

	public static function xAxis():Vec4 { return new Vec4(1, 0, 0); }
	public static function yAxis():Vec4 { return new Vec4(0, 1, 0); }
	public static function zAxis():Vec4 { return new Vec4(0, 0, 1); }

	public function toString():String {
		return this.x + ", " + this.y + ", " + this.z;
	}
}
