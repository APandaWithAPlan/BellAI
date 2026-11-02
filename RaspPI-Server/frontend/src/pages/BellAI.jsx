import { useState, useRef } from "react"
import { Mic, Send, LoaderCircle } from "lucide-react"
import { Message, MessageContent, } from "@/components/ui/message"
import { Bubble, BubbleContent, } from "@/components/ui/bubble"
import {
  MessageScrollerProvider,
  MessageScroller,
  MessageScrollerViewport,
  MessageScrollerContent,
  MessageScrollerItem,
  MessageScrollerButton,
} from "@/components/ui/message-scroller"
import { toast } from "@/components/ui/toast"

function BellAI() {

    const [input, setInput] = useState("")
    const [messages, setMessages] = useState([]);
    const [isRecording, setIsRecording] = useState(false);
    const [isLoading, setIsLoading] = useState(false);

    const mediaRecorderRef = useRef(null);
    const chunksRef = useRef([]); 

    async function startRecording() {
        let stream;

        try {
            stream = await navigator.mediaDevices.getUserMedia({
                audio: true
            });

            const mediaRecorder = new MediaRecorder(stream);

            chunksRef.current = [];

            mediaRecorder.ondataavailable = (event) => {
                if (event.data.size > 0) {
                    chunksRef.current.push(event.data);
                }
            };

            mediaRecorder.onstop = async () => {
                try {
                    const audioBlob = new Blob(chunksRef.current, {
                        type: mediaRecorder.mimeType
                    });

                    const formData = new FormData();
                    formData.append("audio_file", audioBlob, "recording.webm");

                    const response = await fetch("/api/audio", {
                        method: "POST",
                        body: formData
                    });

                    if (!response.ok) {
                        throw new Error("Failed to upload audio.");
                    }

                    const data = await response.json();
                    
                    setMessages(prev => [
                        ...prev,
                        {
                            id: crypto.randomUUID(),
                            role: "user",
                            content: data.transcript
                        },
                        {
                            id: crypto.randomUUID(),
                            role: "assistant",
                            content: data.response
                        }
                    ]);

                } catch (error) {
                    toast.add({
                        type: "warning",
                        description: error.message
                    });
                } finally {
                    stream.getTracks().forEach(track => track.stop());
                    mediaRecorderRef.current = null;
                }
            };

            mediaRecorderRef.current = mediaRecorder;
            mediaRecorder.start();

            setIsRecording(true);

        } catch (error) {
            stream?.getTracks().forEach(track => track.stop());

            toast.add({
                type: "warning",
                description: error.message
            });
        }
    }

    function stopRecording() {
        if (mediaRecorderRef.current?.state === "recording") {
            mediaRecorderRef.current.stop();
            setIsRecording(false);
        }
    }

    async function sendMessage() {
        if (!input.trim()) return;

        const request = input.trim();

        const newMessage = {
            id: crypto.randomUUID(),
            role: "user",
            content: request,
            time: new Date().toLocaleTimeString([], {hour: "numeric", minute: "2-digit"})
        };

        setMessages((prevMessages) => [...prevMessages, newMessage])
        setInput("")

        try {
            setIsLoading(true);

            const response = await fetch("/api/chat", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json"
                },
                body: JSON.stringify({
                    request: request
                })
            });

            if (!response.ok) {
                throw new Error(`Request failed: ${response.status}`);
            }

            const data = await response.json();

            const bellaiMessage = {
                id: crypto.randomUUID(),
                role: "assistant",
                content: data.response,
                time: new Date().toLocaleTimeString([], {hour: "numeric", minute: "2-digit"})
            };

            setMessages(prev => [...prev, bellaiMessage]);

            } catch (error) {
                toast.add({
                    type: "warning",
                    description: error.message
                });
                
            } finally {
                setIsLoading(false);
        }
    }

  return (
    <div className="flex h-[calc(100dvh-120px)] min-h-0 flex-col overflow-hidden bg-[#fff0f7] text-black">
        <div className="min-h-0 flex-1 overflow-hidden">
            <MessageScrollerProvider>
                <MessageScroller className="h-full min-h-0 overflow-hidden">
                    <MessageScrollerViewport>
                        <MessageScrollerContent className="flex flex-col gap-3 p-4">
                            {messages.map((message) => (
                                    <MessageScrollerItem key={message.id} messageId={message.id} scrollAnchor={message.role === "user"}>
                                        <Message align={message.role === "user" ? "end" : "start"}>
                                            <MessageContent>
                                                <div className={`flex w-full gap-2 ${ message.role === "user" ? "justify-end" : "justify-start" }`}>
                                                    {message.role === "assistant" && (
                                                        <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full border border-[#fbcfe8] bg-[#fad5e6] text-xs text-black">
                                                            B
                                                        </div>
                                                    )}
                                                    <div className="flex min-w-0 flex-col gap-1">
                                                <Bubble className="rounded-xl border border-[#fbcfe8] shadow-lg">
                                                    <BubbleContent className={`rounded-xl border px-4 py-3 text-sm text-black ${ message.role === "user" ? "!text-black !border-[#fbcfe8] !bg-[#fad5e6]" : "!text-black !border-[#fbcfe8] !bg-white" }`}>
                                                        {message.content}
                                                    </BubbleContent>
                                                </Bubble>
                                                <span className={`text-xs text-[#be185d] ${ message.role === "user" ? "text-right" : "text-left" }`}>
                                                    {message.time}
                                                </span>
                                            </div>
                                        </div>
                                    </MessageContent>
                                </Message>
                            </MessageScrollerItem>
                        ))}
                        {isLoading && (
                            <div className="flex items-center gap-2 p-3 text-[#be185d]">
                                <LoaderCircle size={20} className="animate-spin"/>
                                <span className="text-sm">
                                    Thinking...
                                </span>
                            </div>
                        )}
                    </MessageScrollerContent>
                </MessageScrollerViewport>
                <MessageScrollerButton />
            </MessageScroller>
        </MessageScrollerProvider>
    </div>

    <div className="flex flex-col items-center gap-3 px-4 py-4">
        <div className="relative flex items-center justify-center">
            {isRecording && (
            <span className="absolute h-14 w-14 animate-ping rounded-full bg-[#f472b6] opacity-50" />
            )}

            <button
            type="button"
            className={`relative z-10 flex h-14 w-14 items-center justify-center rounded-full border transition-colors duration-300 ${
                isRecording
                ? "border-[#be185d] bg-[#be185d] text-white"
                : "border-[#fbcfe8] bg-[#fce7f3] text-[#be185d]"
            }`}
            onClick={isRecording ? stopRecording : startRecording}
            >
            <Mic size={24} />
            </button>
        </div>

        <p className="text-[10px] tracking-[0.2em] text-[#be185d]">
            {isRecording ? "LISTENING..." : "TAP TO SPEAK"}
        </p>
    </div>

      <div className="flex items-center gap-2 border-t border-[#fbcfe8] p-3">
        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="Type a message..."
          className="min-w-0 flex-1 rounded-full border border-[#fbcfe8] bg-[#fce7f3] px-4 py-3 text-sm text-black outline-none placeholder:text-[#be185d]"
        />

        <button
          type="button"
          className="flex h-10 w-10 items-center justify-center rounded-full border border-[#fbcfe8] bg-[#fce7f3] text-[#f472b6]"
          onClick={sendMessage}               
        >
          <Send size={18} fill="#be185d" stroke="#be185d"/>
        </button>
      </div>

</div>
  )
}

export default BellAI