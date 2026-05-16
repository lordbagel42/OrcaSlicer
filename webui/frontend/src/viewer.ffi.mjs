// FFI for the Lustre app:
//  - uploadModel: opens a file picker and POSTs the chosen file as multipart.
//  - <orca-model-viewer src="...">: a Three.js custom element for previewing
//    STL / OBJ / 3MF meshes in the browser.

import * as THREE from "https://esm.sh/three@0.160.0";
import { STLLoader } from "https://esm.sh/three@0.160.0/examples/jsm/loaders/STLLoader.js";
import { OBJLoader } from "https://esm.sh/three@0.160.0/examples/jsm/loaders/OBJLoader.js";
import { ThreeMFLoader } from "https://esm.sh/three@0.160.0/examples/jsm/loaders/3MFLoader.js";
import { OrbitControls } from "https://esm.sh/three@0.160.0/examples/jsm/controls/OrbitControls.js";

export function uploadModel(url, onOk, onErr) {
  const input = document.createElement("input");
  input.type = "file";
  input.accept = ".stl,.3mf,.step,.stp,.obj";
  input.addEventListener("change", () => {
    const file = input.files && input.files[0];
    if (!file) {
      onErr("no file selected");
      return;
    }
    const form = new FormData();
    form.append("model", file, file.name);
    fetch(url, { method: "POST", body: form })
      .then((r) =>
        r.ok ? r.text().then(onOk) : onErr("server returned " + r.status),
      )
      .catch((e) => onErr(String(e)));
  });
  input.click();
}

function loaderFor(src) {
  const lower = src.toLowerCase();
  if (lower.endsWith(".stl")) return new STLLoader();
  if (lower.endsWith(".obj")) return new OBJLoader();
  if (lower.endsWith(".3mf")) return new ThreeMFLoader();
  return null;
}

class OrcaModelViewer extends HTMLElement {
  static get observedAttributes() {
    return ["src"];
  }

  connectedCallback() {
    this._render();
  }

  attributeChangedCallback() {
    if (this.isConnected) this._render();
  }

  disconnectedCallback() {
    if (this._raf) cancelAnimationFrame(this._raf);
  }

  _render() {
    const src = this.getAttribute("src");
    if (!src) return;
    this.innerHTML = "";

    const w = this.clientWidth || 640;
    const h = this.clientHeight || 360;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x06080c);
    const camera = new THREE.PerspectiveCamera(45, w / h, 0.1, 5000);
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(w, h);
    this.appendChild(renderer.domElement);

    scene.add(new THREE.HemisphereLight(0xffffff, 0x303040, 1.2));
    const dir = new THREE.DirectionalLight(0xffffff, 0.8);
    dir.position.set(1, 1, 1);
    scene.add(dir);

    const controls = new OrbitControls(camera, renderer.domElement);

    const loader = loaderFor(src);
    if (!loader) return;

    loader.load(
      src,
      (loaded) => {
        let obj;
        if (loaded.isBufferGeometry) {
          loaded.computeVertexNormals();
          obj = new THREE.Mesh(
            loaded,
            new THREE.MeshStandardMaterial({
              color: 0x2f9f8f,
              metalness: 0.1,
              roughness: 0.6,
            }),
          );
        } else {
          obj = loaded;
        }
        scene.add(obj);

        const box = new THREE.Box3().setFromObject(obj);
        const size = box.getSize(new THREE.Vector3());
        const center = box.getCenter(new THREE.Vector3());
        obj.position.sub(center);
        const maxDim = Math.max(size.x, size.y, size.z) || 100;
        camera.position.set(maxDim, maxDim, maxDim * 1.5);
        camera.lookAt(0, 0, 0);
        controls.update();
      },
      undefined,
      (err) => {
        this.innerHTML =
          '<p style="color:#c66;padding:12px">Could not preview model: ' +
          String(err) +
          "</p>";
      },
    );

    const animate = () => {
      this._raf = requestAnimationFrame(animate);
      controls.update();
      renderer.render(scene, camera);
    };
    animate();
  }
}

if (!customElements.get("orca-model-viewer")) {
  customElements.define("orca-model-viewer", OrcaModelViewer);
}
