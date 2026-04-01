import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { PNG } from 'pngjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Assets are in project root
const ASSETS_DIR = path.join(__dirname, '../../webview-ui/public/assets');

export function loadAssets() {
  const assets = {
    characterSprites: loadCharacterSprites(),
    floorTiles: loadFloorTiles(),
    wallTiles: loadWallTiles(),
    furnitureCatalog: loadFurnitureCatalog(),
    defaultLayout: loadDefaultLayout(),
  };

  return assets;
}

function loadCharacterSprites(): string[][][] {
  // Returns sprite data for 6 character palettes
  const sprites: string[][][] = [];

  for (let i = 0; i < 6; i++) {
    const filePath = path.join(ASSETS_DIR, `characters/char_${i}.png`);
    if (fs.existsSync(filePath)) {
      const png = PNG.sync.read(fs.readFileSync(filePath));
      const spriteData = pngToSpriteData(png);
      sprites.push(spriteData);
    }
  }

  return sprites;
}

function loadFloorTiles(): string[][] {
  const filePath = path.join(ASSETS_DIR, 'floors.png');
  if (fs.existsSync(filePath)) {
    const png = PNG.sync.read(fs.readFileSync(filePath));
    return pngToSpriteData(png);
  }
  return [];
}

function loadWallTiles(): string[][] {
  const filePath = path.join(ASSETS_DIR, 'walls.png');
  if (fs.existsSync(filePath)) {
    const png = PNG.sync.read(fs.readFileSync(filePath));
    return pngToSpriteData(png);
  }
  return [];
}

function loadFurnitureCatalog(): any {
  const filePath = path.join(ASSETS_DIR, 'furniture-catalog.json');
  if (fs.existsSync(filePath)) {
    return JSON.parse(fs.readFileSync(filePath, 'utf-8'));
  }
  return { entries: [] };
}

function loadDefaultLayout(): any {
  const filePath = path.join(ASSETS_DIR, 'default-layout.json');
  if (fs.existsSync(filePath)) {
    return JSON.parse(fs.readFileSync(filePath, 'utf-8'));
  }
  return null;
}

function pngToSpriteData(png: PNG): string[][] {
  const { width, height, data } = png;
  const sprites: string[][] = [];

  for (let y = 0; y < height; y++) {
    const row: string[] = [];
    for (let x = 0; x < width; x++) {
      const idx = (y * width + x) * 4;
      const r = data[idx];
      const g = data[idx + 1];
      const b = data[idx + 2];
      const a = data[idx + 3];

      if (a < 2) {
        row.push(''); // Transparent
      } else {
        const hex = `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`;
        row.push(a < 255 ? `${hex}${a.toString(16).padStart(2, '0')}` : hex);
      }
    }
    sprites.push(row);
  }

  return sprites;
}
