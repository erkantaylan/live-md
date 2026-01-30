// WebSocket client for LiveMD
(function() {
    const content = document.getElementById('content');
    const status = document.getElementById('status');
    const filename = document.getElementById('filename');

    let ws;
    let reconnectDelay = 1000;
    const maxReconnectDelay = 10000;

    function connect() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        ws = new WebSocket(`${protocol}//${window.location.host}/ws`);

        ws.onopen = function() {
            status.textContent = 'live';
            status.className = 'status connected';
            reconnectDelay = 1000;
        };

        ws.onmessage = function(event) {
            const data = JSON.parse(event.data);

            if (data.filename) {
                filename.textContent = data.filename;
                document.title = `${data.filename} - LiveMD`;
            }

            if (data.html) {
                // Save scroll position
                const scrollY = window.scrollY;

                content.innerHTML = data.html;

                // Restore scroll position
                window.scrollTo(0, scrollY);
            }

            if (data.error) {
                content.innerHTML = `<div style="color: #f85149; padding: 20px; background: #ffeef0; border-radius: 6px;">
                    <strong>Error:</strong> ${data.error}
                </div>`;
            }
        };

        ws.onclose = function() {
            status.textContent = 'disconnected';
            status.className = 'status disconnected';

            // Reconnect with exponential backoff
            setTimeout(function() {
                reconnectDelay = Math.min(reconnectDelay * 1.5, maxReconnectDelay);
                connect();
            }, reconnectDelay);
        };

        ws.onerror = function(err) {
            console.error('WebSocket error:', err);
            ws.close();
        };
    }

    connect();
})();
