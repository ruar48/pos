function escapeHtml(text: string): string {
    return text
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

export function printThermalLines(lines: string[]): void {
    const iframe = document.createElement('iframe');
    iframe.setAttribute('aria-hidden', 'true');
    iframe.style.cssText =
        'position:fixed;right:0;bottom:0;width:0;height:0;border:0;opacity:0;pointer-events:none;';
    document.body.appendChild(iframe);

    const frameWindow = iframe.contentWindow;
    const doc = iframe.contentDocument ?? frameWindow?.document;
    if (!doc || !frameWindow) {
        iframe.remove();
        return;
    }

    const body = lines.map(escapeHtml).join('\n');
    doc.open();
    doc.write(`<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Print</title>
<style>
  @page { size: 58mm auto; margin: 1mm; }
  @media print {
    html, body { width: 58mm; margin: 0; padding: 0; }
  }
  body {
    font-family: "Courier New", Courier, monospace;
    font-size: 14px;
    line-height: 1.4;
    color: #000;
    background: #fff;
    margin: 0;
    padding: 3mm 1mm;
  }
  pre {
    margin: 0;
    white-space: pre-wrap;
    word-wrap: break-word;
    text-align: center;
  }
</style>
</head>
<body><pre>${body}</pre></body>
</html>`);
    doc.close();

    const cleanup = () => {
        window.setTimeout(() => iframe.remove(), 1000);
    };

    frameWindow.onafterprint = cleanup;
    frameWindow.focus();
    frameWindow.print();

    window.setTimeout(cleanup, 5000);
}

export async function printThermalCopies(
    lines: string[],
    copies: number,
): Promise<void> {
    const count = Math.max(1, copies);
    for (let i = 0; i < count; i += 1) {
        printThermalLines(lines);
        if (i < count - 1) {
            await new Promise<void>((resolve) => {
                window.setTimeout(resolve, 900);
            });
        }
    }
}
