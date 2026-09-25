import React, { useRef, useMemo, useState, useEffect } from 'react';
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { OrbitControls } from '@react-three/drei';
import * as THREE from 'three';

/* ─── Procedural 3D Eye Anatomy Model ─── */

function Sclera() {
  return (
    <mesh>
      <sphereGeometry args={[1, 64, 64]} />
      <meshStandardMaterial
        color="#f5ece0"
        roughness={0.5}
        metalness={0.01}
      />
    </mesh>
  );
}

function Cornea() {
  return (
    <mesh position={[0, 0, 0.85]}>
      <sphereGeometry args={[0.46, 48, 48, 0, Math.PI * 2, 0, Math.PI / 2.4]} />
      <meshStandardMaterial
        color="#dceef5"
        transparent
        opacity={0.25}
        roughness={0.05}
        metalness={0.1}
        side={THREE.DoubleSide}
      />
    </mesh>
  );
}

function Iris() {
  const irisTexture = useMemo(() => {
    const canvas = document.createElement('canvas');
    canvas.width = 512;
    canvas.height = 512;
    const ctx = canvas.getContext('2d');
    const cx = 256, cy = 256;

    // Base iris color - rich brown
    const grad = ctx.createRadialGradient(cx, cy, 15, cx, cy, 240);
    grad.addColorStop(0, '#1a0a04');
    grad.addColorStop(0.15, '#3d1c08');
    grad.addColorStop(0.35, '#6b3510');
    grad.addColorStop(0.55, '#8b5625');
    grad.addColorStop(0.75, '#a0703a');
    grad.addColorStop(0.9, '#7a4820');
    grad.addColorStop(1.0, '#4a2508');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, 512, 512);

    // Radial fiber pattern
    ctx.globalAlpha = 0.4;
    for (let i = 0; i < 220; i++) {
      const angle = (i / 220) * Math.PI * 2 + Math.random() * 0.03;
      const innerR = 25 + Math.random() * 25;
      const outerR = 140 + Math.random() * 80;
      ctx.beginPath();
      ctx.moveTo(cx + Math.cos(angle) * innerR, cy + Math.sin(angle) * innerR);
      ctx.lineTo(cx + Math.cos(angle) * outerR, cy + Math.sin(angle) * outerR);
      const hue = 22 + Math.random() * 18;
      const sat = 45 + Math.random() * 35;
      const lum = 25 + Math.random() * 30;
      ctx.strokeStyle = `hsl(${hue}, ${sat}%, ${lum}%)`;
      ctx.lineWidth = 0.8 + Math.random() * 2.2;
      ctx.stroke();
    }
    ctx.globalAlpha = 1;

    // Deep pupil center
    const pupilGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, 55);
    pupilGrad.addColorStop(0, '#000000');
    pupilGrad.addColorStop(0.85, '#030100');
    pupilGrad.addColorStop(1.0, 'rgba(3,1,0,0)');
    ctx.fillStyle = pupilGrad;
    ctx.beginPath();
    ctx.arc(cx, cy, 55, 0, Math.PI * 2);
    ctx.fill();

    // Limbal ring
    ctx.beginPath();
    ctx.arc(cx, cy, 225, 0, Math.PI * 2);
    ctx.strokeStyle = 'rgba(20, 10, 3, 0.7)';
    ctx.lineWidth = 8;
    ctx.stroke();

    // Collarette ring
    ctx.beginPath();
    ctx.arc(cx, cy, 110, 0, Math.PI * 2);
    ctx.strokeStyle = 'rgba(160, 110, 60, 0.25)';
    ctx.lineWidth = 3;
    ctx.stroke();

    const tex = new THREE.CanvasTexture(canvas);
    tex.needsUpdate = true;
    return tex;
  }, []);

  return (
    <mesh position={[0, 0, 0.82]}>
      <circleGeometry args={[0.34, 64]} />
      <meshStandardMaterial
        map={irisTexture}
        roughness={0.35}
        metalness={0.05}
      />
    </mesh>
  );
}

function Pupil() {
  return (
    <mesh position={[0, 0, 0.83]}>
      <circleGeometry args={[0.11, 48]} />
      <meshStandardMaterial color="#010000" roughness={0.95} metalness={0} />
    </mesh>
  );
}

function CrystallineLens() {
  return (
    <group position={[0, 0, 0.5]}>
      <mesh>
        <sphereGeometry args={[0.33, 32, 32, 0, Math.PI * 2, 0, Math.PI / 3]} />
        <meshStandardMaterial
          color="#f8f3ea"
          transparent
          opacity={0.12}
          roughness={0.05}
        />
      </mesh>
      <mesh rotation={[Math.PI, 0, 0]} position={[0, 0, -0.1]}>
        <sphereGeometry args={[0.28, 32, 32, 0, Math.PI * 2, 0, Math.PI / 3.5]} />
        <meshStandardMaterial
          color="#f8f3ea"
          transparent
          opacity={0.1}
          roughness={0.05}
        />
      </mesh>
    </group>
  );
}

function OpticNerve() {
  const curve = useMemo(() => {
    return new THREE.CatmullRomCurve3([
      new THREE.Vector3(0, 0, -1.0),
      new THREE.Vector3(-0.04, -0.02, -1.3),
      new THREE.Vector3(-0.1, -0.06, -1.65),
      new THREE.Vector3(-0.12, -0.12, -2.0),
      new THREE.Vector3(-0.08, -0.18, -2.4),
    ]);
  }, []);

  return (
    <mesh>
      <tubeGeometry args={[curve, 32, 0.14, 16, false]} />
      <meshStandardMaterial
        color="#e8dccb"
        roughness={0.6}
        metalness={0.02}
      />
    </mesh>
  );
}

function BloodVessel({ points, radius = 0.018, color = '#b83030' }) {
  const curve = useMemo(() => {
    return new THREE.CatmullRomCurve3(
      points.map(p => new THREE.Vector3(...p))
    );
  }, [points]);

  return (
    <mesh>
      <tubeGeometry args={[curve, 24, radius, 8, false]} />
      <meshStandardMaterial color={color} roughness={0.5} metalness={0.06} />
    </mesh>
  );
}

function BloodVessels() {
  const vesselPaths = useMemo(() => {
    const vessels = [];
    const r = 1.008;

    const createVesselPath = (startTheta, startPhi, segments, spread, seed) => {
      const points = [];
      let theta = startTheta;
      let phi = startPhi;
      for (let i = 0; i < segments; i++) {
        const t = i / segments;
        theta += spread * (0.08 + Math.sin(seed + t * 5) * 0.04);
        phi += spread * (Math.cos(seed + t * 7) * 0.06);
        const x = r * Math.sin(phi) * Math.cos(theta);
        const y = r * Math.sin(phi) * Math.sin(theta);
        const z = r * Math.cos(phi);
        points.push([x, y, z]);
      }
      return points;
    };

    vessels.push({ points: createVesselPath(0.5, 1.8, 12, 0.7, 1), radius: 0.024, color: '#c03030' });
    vessels.push({ points: createVesselPath(2.1, 1.4, 10, 0.8, 2), radius: 0.022, color: '#b82828' });
    vessels.push({ points: createVesselPath(3.8, 1.2, 14, 0.5, 3), radius: 0.02, color: '#a83535' });
    vessels.push({ points: createVesselPath(5.2, 2.0, 11, 0.6, 4), radius: 0.018, color: '#c04040' });
    vessels.push({ points: createVesselPath(1.2, 2.2, 8, 0.9, 5), radius: 0.014, color: '#903030' });
    vessels.push({ points: createVesselPath(4.1, 0.9, 9, 0.7, 6), radius: 0.015, color: '#982525' });
    vessels.push({ points: createVesselPath(0.8, 1.0, 10, 0.6, 7), radius: 0.013, color: '#882828' });
    vessels.push({ points: createVesselPath(2.8, 2.5, 7, 0.8, 8), radius: 0.016, color: '#a02020' });

    return vessels;
  }, []);

  return (
    <group>
      {vesselPaths.map((vessel, i) => (
        <BloodVessel key={i} {...vessel} />
      ))}
    </group>
  );
}

function ExtraocularMuscle({ startAngle, endPos, color = '#cc5555' }) {
  const geometry = useMemo(() => {
    const curve = new THREE.CatmullRomCurve3([
      new THREE.Vector3(
        1.04 * Math.cos(startAngle),
        1.04 * Math.sin(startAngle),
        -0.25
      ),
      new THREE.Vector3(
        1.25 * Math.cos(startAngle),
        1.25 * Math.sin(startAngle),
        -0.65
      ),
      new THREE.Vector3(endPos[0], endPos[1], endPos[2]),
    ]);
    return new THREE.TubeGeometry(curve, 16, 0.09, 8, false);
  }, [startAngle, endPos]);

  return (
    <mesh geometry={geometry}>
      <meshStandardMaterial
        color={color}
        roughness={0.55}
        metalness={0.04}
        side={THREE.DoubleSide}
      />
    </mesh>
  );
}

function ExtraocularMuscles() {
  const muscles = useMemo(() => [
    { startAngle: Math.PI / 2, endPos: [0, 1.6, -2.1], color: '#c44444' },
    { startAngle: -Math.PI / 2, endPos: [0, -1.6, -2.1], color: '#cc5050' },
    { startAngle: Math.PI, endPos: [-1.6, 0, -2.1], color: '#c04848' },
    { startAngle: 0, endPos: [1.6, 0, -2.1], color: '#c84040' },
    { startAngle: Math.PI * 0.75, endPos: [-0.9, 1.4, -2.3], color: '#b84040' },
    { startAngle: -Math.PI * 0.75, endPos: [-0.9, -1.4, -2.3], color: '#b04848' },
  ], []);

  return (
    <group>
      {muscles.map((m, i) => (
        <ExtraocularMuscle key={i} {...m} />
      ))}
    </group>
  );
}

function EyeAssembly() {
  const groupRef = useRef();

  useFrame((state) => {
    if (groupRef.current) {
      const t = state.clock.elapsedTime;
      groupRef.current.rotation.y = Math.sin(t * 0.25) * 0.18 + 0.3;
      groupRef.current.rotation.x = Math.sin(t * 0.18) * 0.08 - 0.05;
    }
  });

  return (
    <group ref={groupRef} position={[0, 0, 0]} scale={1.1}>
      <Sclera />
      <Cornea />
      <Iris />
      <Pupil />
      <CrystallineLens />
      <OpticNerve />
      <BloodVessels />
      <ExtraocularMuscles />
    </group>
  );
}

/* ─── WebGL availability check ─── */
function isWebGLAvailable() {
  try {
    const canvas = document.createElement('canvas');
    return !!(window.WebGLRenderingContext && 
      (canvas.getContext('webgl') || canvas.getContext('experimental-webgl')));
  } catch (e) {
    return false;
  }
}

/* ─── Fallback when WebGL is not available ─── */
function WebGLFallback() {
  return (
    <div className="eye3d-fallback">
      <div className="eye3d-fallback-sphere">
        <div className="eye3d-fallback-iris">
          <div className="eye3d-fallback-pupil" />
        </div>
      </div>
      <p>3D model requires WebGL support</p>
    </div>
  );
}

export default function EyeModel3D() {
  const [webglOk, setWebglOk] = useState(true);

  useEffect(() => {
    setWebglOk(isWebGLAvailable());
  }, []);

  if (!webglOk) {
    return <WebGLFallback />;
  }

  return (
    <div className="eye-3d-container">
      <Canvas
        camera={{ position: [1.8, 0.8, 2.8], fov: 40 }}
        gl={{ 
          antialias: true, 
          alpha: true,
          powerPreference: 'default',
          failIfMajorPerformanceCaveat: false,
        }}
        style={{ background: 'transparent' }}
        dpr={[1, 1.5]}
        onCreated={({ gl }) => {
          gl.toneMapping = THREE.ACESFilmicToneMapping;
          gl.toneMappingExposure = 1.2;
        }}
      >
        {/* Simple but effective lighting - no Environment preset, no shadows */}
        <ambientLight intensity={0.6} color="#f8f0e8" />
        
        {/* Key Light */}
        <directionalLight
          position={[5, 5, 5]}
          intensity={2.0}
          color="#fff5e8"
        />
        
        {/* Fill Light */}
        <directionalLight
          position={[-4, -2, 3]}
          intensity={0.8}
          color="#b0d0f0"
        />
        
        {/* Rim Light */}
        <directionalLight
          position={[0, 3, -4]}
          intensity={0.6}
          color="#f0d8c0"
        />
        
        {/* Specular highlights */}
        <pointLight position={[0, 0.5, 3]} intensity={1.0} color="#ffe8d0" distance={8} />
        <pointLight position={[3, -1, -2]} intensity={0.5} color="#d0e8ff" distance={10} />

        {/* Hemisphere light for natural fill */}
        <hemisphereLight
          color="#f0e8ff"
          groundColor="#d0c8b0"
          intensity={0.4}
        />

        {/* Eye Model */}
        <EyeAssembly />

        {/* Controls */}
        <OrbitControls
          enableZoom={false}
          enablePan={false}
          autoRotate={false}
          minPolarAngle={Math.PI / 5}
          maxPolarAngle={Math.PI * 4 / 5}
          dampingFactor={0.08}
          rotateSpeed={0.5}
          target={[0, 0, -0.3]}
        />
      </Canvas>
    </div>
  );
}
