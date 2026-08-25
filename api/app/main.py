import os
import uuid

import boto3
from botocore.exceptions import ClientError
from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

BUCKET_NAME = os.environ["BUCKET_NAME"]
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
PRESIGN_EXPIRY_SECONDS = int(os.environ.get("PRESIGN_EXPIRY_SECONDS", "900"))

s3 = boto3.client("s3", region_name=AWS_REGION)

app = FastAPI(title="ComplyFlow API")


class PresignRequest(BaseModel):
    filename: str
    content_type: str = "application/octet-stream"


class PresignResponse(BaseModel):
    file_id: str
    key: str
    upload_url: str
    expires_in: int


@app.get("/health")
def health():
    return {"status": "ok"}


UPLOAD_PAGE = """
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>DocFlow — Upload</title>
<style>
  :root {
    --bg: #f7f8fa;
    --card: #ffffff;
    --border: #e5e7eb;
    --text: #14161a;
    --muted: #6b7280;
    --accent: #2563eb;
    --accent-hover: #1d4ed8;
    --accent-soft: #eff4ff;
    --success: #16a34a;
    --danger: #dc2626;
    --radius: 12px;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Inter, Roboto, Helvetica, Arial, sans-serif;
    background: var(--bg);
    color: var(--text);
    min-height: 100vh;
  }

  nav {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 32px;
    height: 64px;
    background: var(--card);
    border-bottom: 1px solid var(--border);
    position: sticky;
    top: 0;
    z-index: 10;
  }
  .brand {
    display: flex;
    align-items: center;
    gap: 10px;
    font-weight: 700;
    font-size: 17px;
    color: var(--text);
    text-decoration: none;
  }
  .brand-mark {
    width: 28px;
    height: 28px;
    border-radius: 8px;
    background: linear-gradient(135deg, var(--accent), #60a5fa);
    display: flex;
    align-items: center;
    justify-content: center;
    color: white;
    font-size: 14px;
    font-weight: 800;
  }
  .nav-links {
    display: flex;
    align-items: center;
    gap: 4px;
  }
  .nav-links a {
    color: var(--muted);
    text-decoration: none;
    font-size: 14px;
    font-weight: 500;
    padding: 8px 14px;
    border-radius: 8px;
    transition: background 0.15s, color 0.15s;
  }
  .nav-links a:hover {
    background: var(--accent-soft);
    color: var(--accent);
  }
  .nav-links a.active {
    background: var(--accent-soft);
    color: var(--accent);
  }

  main {
    max-width: 560px;
    margin: 0 auto;
    padding: 64px 24px;
  }
  .eyebrow {
    text-align: center;
    color: var(--accent);
    font-size: 13px;
    font-weight: 700;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    margin-bottom: 8px;
  }
  h1 {
    text-align: center;
    font-size: 28px;
    margin: 0 0 8px;
    letter-spacing: -0.02em;
  }
  .subtitle {
    text-align: center;
    color: var(--muted);
    font-size: 15px;
    margin: 0 0 32px;
  }

  .card {
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 32px;
    box-shadow: 0 1px 2px rgba(16, 24, 40, 0.04);
  }

  .dropzone {
    border: 2px dashed var(--border);
    border-radius: var(--radius);
    padding: 36px 20px;
    text-align: center;
    cursor: pointer;
    transition: border-color 0.15s, background 0.15s;
  }
  .dropzone:hover, .dropzone.dragover {
    border-color: var(--accent);
    background: var(--accent-soft);
  }
  .dropzone svg { color: var(--muted); margin-bottom: 10px; }
  .dropzone-title { font-weight: 600; font-size: 15px; margin-bottom: 4px; }
  .dropzone-hint { color: var(--muted); font-size: 13px; }
  #file { display: none; }

  .file-row {
    display: none;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    margin-top: 16px;
    padding: 12px 14px;
    background: var(--accent-soft);
    border-radius: 8px;
    font-size: 14px;
  }
  .file-row.visible { display: flex; }
  .file-name { font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .file-remove {
    background: none;
    border: none;
    color: var(--muted);
    cursor: pointer;
    font-size: 16px;
    line-height: 1;
    padding: 4px;
  }
  .file-remove:hover { color: var(--danger); }

  button.primary {
    width: 100%;
    margin-top: 20px;
    padding: 12px 16px;
    background: var(--accent);
    color: white;
    border: none;
    border-radius: 8px;
    font-size: 15px;
    font-weight: 600;
    cursor: pointer;
    transition: background 0.15s, opacity 0.15s;
  }
  button.primary:hover { background: var(--accent-hover); }
  button.primary:disabled { opacity: 0.5; cursor: not-allowed; }

  .progress-track {
    display: none;
    margin-top: 18px;
    height: 8px;
    background: var(--border);
    border-radius: 999px;
    overflow: hidden;
  }
  .progress-track.visible { display: block; }
  .progress-fill {
    height: 100%;
    width: 0%;
    background: var(--accent);
    border-radius: 999px;
    transition: width 0.15s ease;
  }

  .status {
    margin-top: 16px;
    font-size: 14px;
    text-align: center;
    color: var(--muted);
    min-height: 20px;
  }
  .status.success { color: var(--success); font-weight: 600; }
  .status.error { color: var(--danger); font-weight: 600; }

  .pipeline-note {
    margin-top: 24px;
    text-align: center;
    color: var(--muted);
    font-size: 12.5px;
    line-height: 1.6;
  }
  .pipeline-note code {
    background: var(--accent-soft);
    color: var(--accent);
    padding: 1px 5px;
    border-radius: 4px;
    font-size: 12px;
  }
</style>
</head>
<body>
  <nav>
    <a class="brand" href="/upload">
      <span class="brand-mark">DF</span>
      DocFlow
    </a>
    <div class="nav-links">
      <a class="active" href="/upload">Upload</a>
      <a href="/docs" target="_blank" rel="noopener">API Docs</a>
      <a href="/health" target="_blank" rel="noopener">Health</a>
    </div>
  </nav>

  <main>
    <div class="eyebrow">Document Processing Pipeline</div>
    <h1>Upload a document</h1>
    <p class="subtitle">Files are uploaded directly to S3 via a presigned URL and picked up by the async processing pipeline.</p>

    <div class="card">
      <div class="dropzone" id="dropzone">
        <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>
        <div class="dropzone-title">Click to choose a file, or drag it here</div>
        <div class="dropzone-hint">Any file type · presigned direct-to-S3 upload</div>
      </div>
      <input type="file" id="file">

      <div class="file-row" id="fileRow">
        <span class="file-name" id="fileName"></span>
        <button class="file-remove" id="fileRemove" title="Remove file">&times;</button>
      </div>

      <button class="primary" id="uploadBtn" disabled>Upload</button>

      <div class="progress-track" id="progressTrack">
        <div class="progress-fill" id="progressFill"></div>
      </div>

      <p class="status" id="status"></p>
    </div>

    <p class="pipeline-note">
      Upload triggers <code>S3 → SQS → Lambda → DynamoDB → SNS</code> processing and notification fan-out.
    </p>
  </main>

  <script>
    const dropzone = document.getElementById('dropzone');
    const fileInput = document.getElementById('file');
    const fileRow = document.getElementById('fileRow');
    const fileName = document.getElementById('fileName');
    const fileRemove = document.getElementById('fileRemove');
    const uploadBtn = document.getElementById('uploadBtn');
    const status = document.getElementById('status');
    const progressTrack = document.getElementById('progressTrack');
    const progressFill = document.getElementById('progressFill');

    function setFile(file) {
      if (!file) return;
      fileInput.files = makeFileList(file);
      fileName.textContent = file.name;
      fileRow.classList.add('visible');
      uploadBtn.disabled = false;
      status.textContent = '';
      status.className = 'status';
    }

    function makeFileList(file) {
      const dt = new DataTransfer();
      dt.items.add(file);
      return dt.files;
    }

    function clearFile() {
      fileInput.value = '';
      fileRow.classList.remove('visible');
      uploadBtn.disabled = true;
      progressTrack.classList.remove('visible');
      progressFill.style.width = '0%';
    }

    dropzone.addEventListener('click', () => fileInput.click());
    fileInput.addEventListener('change', () => {
      if (fileInput.files[0]) setFile(fileInput.files[0]);
    });
    fileRemove.addEventListener('click', (e) => { e.stopPropagation(); clearFile(); });

    ['dragenter', 'dragover'].forEach(evt =>
      dropzone.addEventListener(evt, (e) => {
        e.preventDefault();
        dropzone.classList.add('dragover');
      })
    );
    ['dragleave', 'drop'].forEach(evt =>
      dropzone.addEventListener(evt, (e) => {
        e.preventDefault();
        dropzone.classList.remove('dragover');
      })
    );
    dropzone.addEventListener('drop', (e) => {
      const file = e.dataTransfer.files[0];
      if (file) setFile(file);
    });

    function putWithProgress(url, file) {
      return new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        xhr.open('PUT', url);
        xhr.setRequestHeader('Content-Type', file.type || 'application/octet-stream');
        xhr.upload.onprogress = (e) => {
          if (e.lengthComputable) {
            const pct = Math.round((e.loaded / e.total) * 100);
            progressFill.style.width = pct + '%';
          }
        };
        xhr.onload = () => (xhr.status >= 200 && xhr.status < 300) ? resolve() : reject(new Error('Upload failed (' + xhr.status + ')'));
        xhr.onerror = () => reject(new Error('Upload failed'));
        xhr.send(file);
      });
    }

    async function upload() {
      const file = fileInput.files[0];
      if (!file) return;

      uploadBtn.disabled = true;
      progressTrack.classList.add('visible');
      progressFill.style.width = '0%';
      status.className = 'status';
      status.textContent = 'Requesting upload URL...';

      try {
        const presignRes = await fetch('/presign', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            filename: file.name,
            content_type: file.type || 'application/octet-stream'
          })
        });
        if (!presignRes.ok) throw new Error('Failed to get upload URL');
        const presignData = await presignRes.json();

        status.textContent = 'Uploading...';
        await putWithProgress(presignData.upload_url, file);

        status.textContent = 'Uploaded: ' + presignData.file_id;
        status.className = 'status success';
      } catch (err) {
        status.textContent = err.message || 'Something went wrong';
        status.className = 'status error';
        uploadBtn.disabled = false;
      }
    }

    uploadBtn.addEventListener('click', upload);
  </script>
</body>
</html>
"""


@app.get("/upload", response_class=HTMLResponse)
def upload_page():
    return UPLOAD_PAGE


@app.post("/presign", response_model=PresignResponse)
def create_presigned_upload(req: PresignRequest):
    file_id = f"{uuid.uuid4()}-{req.filename}"
    key = f"uploads/{file_id}"

    try:
        upload_url = s3.generate_presigned_url(
            ClientMethod="put_object",
            Params={
                "Bucket": BUCKET_NAME,
                "Key": key,
                "ContentType": req.content_type,
            },
            ExpiresIn=PRESIGN_EXPIRY_SECONDS,
        )
    except ClientError as exc:
        raise HTTPException(status_code=500, detail="failed to generate upload URL") from exc

    return PresignResponse(
        file_id=file_id,
        key=key,
        upload_url=upload_url,
        expires_in=PRESIGN_EXPIRY_SECONDS,
    )
