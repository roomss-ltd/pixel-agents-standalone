import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

const PIXEL_AGENTS_DIR = path.join(os.homedir(), '.pixel-agents');
const LAYOUT_FILE = path.join(PIXEL_AGENTS_DIR, 'layout.json');
const AGENT_SEATS_FILE = path.join(PIXEL_AGENTS_DIR, 'agent-seats.json');
const SETTINGS_FILE = path.join(PIXEL_AGENTS_DIR, 'settings.json');

// Ensure directory exists
if (!fs.existsSync(PIXEL_AGENTS_DIR)) {
  fs.mkdirSync(PIXEL_AGENTS_DIR, { recursive: true });
}

export interface AgentSeatData {
  seatId?: string;
  palette?: number;
  hueShift?: number;
}

export interface Settings {
  soundEnabled: boolean;
  showInactiveSessions: boolean;
}

// Layout persistence
export function readLayout(): any {
  try {
    if (fs.existsSync(LAYOUT_FILE)) {
      return JSON.parse(fs.readFileSync(LAYOUT_FILE, 'utf-8'));
    }
  } catch (err) {
    console.error('[Persistence] Failed to read layout:', err);
  }
  return null;
}

export function writeLayout(layout: any): void {
  try {
    const tmpFile = `${LAYOUT_FILE}.tmp`;
    fs.writeFileSync(tmpFile, JSON.stringify(layout, null, 2));
    fs.renameSync(tmpFile, LAYOUT_FILE);
    console.log('[Persistence] Layout saved');
  } catch (err) {
    console.error('[Persistence] Failed to write layout:', err);
  }
}

// Agent seats persistence
export function readAgentSeats(): Record<string, AgentSeatData> {
  try {
    if (fs.existsSync(AGENT_SEATS_FILE)) {
      return JSON.parse(fs.readFileSync(AGENT_SEATS_FILE, 'utf-8'));
    }
  } catch (err) {
    console.error('[Persistence] Failed to read agent seats:', err);
  }
  return {};
}

export function writeAgentSeats(seats: Record<string, AgentSeatData>): void {
  try {
    fs.writeFileSync(AGENT_SEATS_FILE, JSON.stringify(seats, null, 2));
    console.log('[Persistence] Agent seats saved');
  } catch (err) {
    console.error('[Persistence] Failed to write agent seats:', err);
  }
}

// Settings persistence
export function readSettings(): Settings {
  try {
    if (fs.existsSync(SETTINGS_FILE)) {
      return JSON.parse(fs.readFileSync(SETTINGS_FILE, 'utf-8'));
    }
  } catch (err) {
    console.error('[Persistence] Failed to read settings:', err);
  }
  return {
    soundEnabled: true,
    showInactiveSessions: true,
  };
}

export function writeSettings(settings: Settings): void {
  try {
    fs.writeFileSync(SETTINGS_FILE, JSON.stringify(settings, null, 2));
    console.log('[Persistence] Settings saved');
  } catch (err) {
    console.error('[Persistence] Failed to write settings:', err);
  }
}

// Watch layout file for external changes
export function watchLayoutFile(callback: (layout: any) => void): fs.FSWatcher | null {
  try {
    let lastMtime = fs.existsSync(LAYOUT_FILE) ? fs.statSync(LAYOUT_FILE).mtimeMs : 0;

    return fs.watch(LAYOUT_FILE, () => {
      try {
        const currentMtime = fs.statSync(LAYOUT_FILE).mtimeMs;
        if (currentMtime !== lastMtime) {
          lastMtime = currentMtime;
          const layout = readLayout();
          if (layout) {
            callback(layout);
          }
        }
      } catch {
        /* ignore */
      }
    });
  } catch (err) {
    console.error('[Persistence] Failed to watch layout file:', err);
    return null;
  }
}
