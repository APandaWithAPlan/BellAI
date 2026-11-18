
import { useEffect, useRef, useState } from "react";
import { toast } from "@/components/ui/toast";

export function useChatWebSocket() {
    const [messages, setMessages] = useState([]);
    const [isLoading, setIsLoading] = useState(false);
    const [isConnected, setIsConnected] = useState(false);

    const socketRef = useRef(null);
    const activeMessageRef = useRef(null);
    const pendingRef = useRef(false);

    const audioQueueRef = useRef([]);
    const playingRef = useRef(false);
    const audioRef = useRef(null);

    useEffect(() => {
        let active = true;

        const socket = new WebSocket(`ws://${window.location.host}/ws/chat`);

        socket.binaryType = "arraybuffer";
        socketRef.current = socket;

        socket.onopen = () => {
            if (active) setIsConnected(true);
        };

        socket.onmessage = (event) => {
            if (!active) return;

            if (typeof event.data !== "string") {
                audioQueueRef.current.push(event.data);
                playNextAudio();
                return;
            }

            const data = JSON.parse(event.data);

            switch (data.type) {
                case "text":
                    setMessages(prev =>
                        prev.map(message =>
                            message.id === activeMessageRef.current
                                ? {
                                    ...message,
                                    content: message.content + data.delta
                                }
                                : message
                        )
                    );
                    break;

                case "sentence":
                    break;

                case "done":
                    pendingRef.current = false;
                    activeMessageRef.current = null;
                    setIsLoading(false);
                    break;

                case "tts_error":
                    toast.add({
                        type: "warning",
                        description: data.message
                    });
                    break;

                case "error":
                    pendingRef.current = false;
                    activeMessageRef.current = null;
                    setIsLoading(false);
                    toast.add({
                        type: "error",
                        description: data.message
                    });
                    break;
            }
        };

        socket.onerror = () => {
            if (active) {
                toast.add({
                    type: "error",
                    description: "BellAI WebSocket connection failed."
                });
            }
        };

        socket.onclose = () => {
            if (active) {
                setIsConnected(false);
                setIsLoading(false);
                pendingRef.current = false;
                activeMessageRef.current = null;
            }
        };

        return () => {
            active = false;

            if (socket.readyState === WebSocket.OPEN) {
                socket.close();
            } else if (socket.readyState === WebSocket.CONNECTING) {
                socket.addEventListener("open", () => socket.close(), { once: true });
            }

            if (socketRef.current === socket) {
                socketRef.current = null;
            }

            audioQueueRef.current = [];
            audioRef.current?.pause();
            audioRef.current = null;
        };
    }, []);

    async function playNextAudio() {
        if (playingRef.current || audioQueueRef.current.length === 0) {
            return;
        }

        playingRef.current = true;

        const audioData = audioQueueRef.current.shift();
        const blob = new Blob([audioData], { type: "audio/wav" });
        const url = URL.createObjectURL(blob);
        const audio = new Audio(url);

        audioRef.current = audio;

        try {
            await audio.play();

            await new Promise((resolve) => {
                audio.onended = resolve;
                audio.onerror = resolve;
            });

        } catch (error) {
            console.error("Audio playback failed:", error);

        } finally {
            URL.revokeObjectURL(url);
            audioRef.current = null;
            playingRef.current = false;
            playNextAudio();
        }
    }

    function sendToBellAI(request) {
        const socket = socketRef.current;

        if (!request.trim() ||
            socket?.readyState !== WebSocket.OPEN ||
            pendingRef.current) {
            return false;
        }

        const assistantId = crypto.randomUUID();

        pendingRef.current = true;
        activeMessageRef.current = assistantId;
        setIsLoading(true);

        const time = new Date().toLocaleTimeString([], {
            hour: "numeric",
            minute: "2-digit"
        });

        setMessages(prev => [
            ...prev,
            {
                id: crypto.randomUUID(),
                role: "user",
                content: request,
                time
            },
            {
                id: assistantId,
                role: "assistant",
                content: "",
                time
            }
        ]);

        socket.send(JSON.stringify({
            messages: [
                {
                    role: "user",
                    content: request
                }
            ]
        }));

        return true;
    }

    return {
        messages,
        isLoading,
        isConnected,
        sendToBellAI
    };
}
