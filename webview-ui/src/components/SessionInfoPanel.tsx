import { useEffect, useState } from 'react';

interface SessionInfo {
  id: number;
  sessionId: string;
  projectPath: string;
  projectName: string;
  jsonlFile: string;
  lastModified: number;
  fileSize: number;
  isActive: boolean;
}

interface Props {
  agentId: number | null;
  sendMessage: (message: any) => void;
  onClose: () => void;
}

export function SessionInfoPanel({ agentId, sendMessage, onClose }: Props) {
  const [info, setInfo] = useState<SessionInfo | null>(null);

  useEffect(() => {
    if (agentId === null) return;

    // Request session info
    sendMessage({ type: 'getSessionInfo', id: agentId });

    // Listen for response
    const handleMessage = (event: MessageEvent) => {
      try {
        const message = event.data;
        if (message.type === 'sessionInfo' && message.id === agentId) {
          setInfo(message.info);
        }
      } catch {
        /* ignore */
      }
    };

    window.addEventListener('message', handleMessage);
    return () => window.removeEventListener('message', handleMessage);
  }, [agentId, sendMessage]);

  if (!info) return null;

  const lastActiveAgo = Math.floor((Date.now() - info.lastModified) / 1000);
  const lastActiveText =
    lastActiveAgo < 60
      ? `${lastActiveAgo}s ago`
      : lastActiveAgo < 3600
        ? `${Math.floor(lastActiveAgo / 60)}m ago`
        : `${Math.floor(lastActiveAgo / 3600)}h ago`;

  return (
    <div
      style={{
        position: 'fixed',
        top: '50%',
        left: '50%',
        transform: 'translate(-50%, -50%)',
        backgroundColor: 'var(--pixel-bg)',
        border: '2px solid var(--pixel-border)',
        boxShadow: '4px 4px 0px var(--pixel-shadow)',
        padding: '16px',
        minWidth: '400px',
        zIndex: 10000,
      }}
    >
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          marginBottom: '12px',
        }}
      >
        <h3 style={{ margin: 0, fontSize: '16px' }}>Agent #{info.id}</h3>
        <button
          onClick={onClose}
          style={{
            background: '#e76f51',
            border: '2px solid var(--pixel-border)',
            borderRadius: 0,
            color: 'white',
            padding: '4px 8px',
            cursor: 'pointer',
            fontSize: '14px',
          }}
        >
          ✕
        </button>
      </div>

      <div style={{ fontSize: '14px', lineHeight: '1.6' }}>
        <div>
          <strong>Session ID:</strong> {info.sessionId}
        </div>
        <div>
          <strong>Project:</strong> {info.projectName}
        </div>
        <div>
          <strong>Path:</strong> {info.projectPath}
        </div>
        <div>
          <strong>Status:</strong> {info.isActive ? '🟢 Active' : '🟡 Idle'}
        </div>
        <div>
          <strong>Last Activity:</strong> {lastActiveText}
        </div>
        <div>
          <strong>Transcript Size:</strong> {Math.round(info.fileSize / 1024)} KB
        </div>
      </div>

      <div
        style={{
          marginTop: '16px',
          padding: '12px',
          backgroundColor: 'rgba(255,255,255,0.05)',
          border: '2px solid var(--pixel-border)',
          borderRadius: 0,
          fontSize: '12px',
        }}
      >
        <div style={{ marginBottom: '8px' }}>
          <strong>To interact with this agent:</strong>
        </div>
        <div>Go to your terminal running this Claude session</div>
        <div style={{ marginTop: '4px', fontFamily: 'monospace', color: '#8be9fd' }}>
          Session: {info.sessionId}
        </div>
      </div>
    </div>
  );
}
