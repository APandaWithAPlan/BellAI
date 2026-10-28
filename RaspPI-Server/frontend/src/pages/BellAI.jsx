import { useState } from "react"
import { Mic, Send } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
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

function BellAI() {

    const [input, setInput] = useState("")

    const [messages, setMessages] = useState([
        { id: "1", role: "user", content: "Hello BellAI!", time: "10:30 PM"},
        { id: "2", role: "assistant", content: "Hello! How can I help?", time: "10:31 PM" },
        { id: "3", role: "user", content: "How's the weather?", time: "10:32 PM"},
        { id: "4", role: "assistant", content: "It's sunny.", time: "10:32 PM" },
    ])

  return (
    <div className="flex min-h-[calc(100dvh-120px)] flex-col bg-[#0c0709] text-white">
        <div className="min-h-0 flex-1">
            <MessageScrollerProvider>
                <MessageScroller  className="h-full min-h-0">
                    <MessageScrollerViewport>
                        <MessageScrollerContent className="flex flex-col gap-3 p-4">
                            {messages.map((message) => (
                                    <MessageScrollerItem key={message.id} messageId={message.id} scrollAnchor={message.role === "user"}>
                                        <Message align={message.role === "user" ? "end" : "start"}>
                                            <MessageContent>
                                                <div className={`flex w-full gap-2 ${ message.role === "user" ? "justify-end" : "justify-start" }`}>
                                                    {message.role === "assistant" && (
                                                        <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full border border-[#7d5070] bg-[#301623] text-xs text-[#f472b6]">
                                                            B
                                                        </div>
                                                    )}
                                                    <div className="flex min-w-0 flex-col gap-1">
                                                <Bubble>
                                                    <BubbleContent className={`rounded-xl border px-4 py-3 text-sm text-white ${ message.role === "user" ? "!border-[#d0629c] !bg-[#39212e]" : "border-[#39212e] bg-[#20151c]" }`}>
                                                        {message.content}
                                                    </BubbleContent>
                                                </Bubble>
                                                <span className={`text-xs text-[#a35b89] ${ message.role === "user" ? "text-right" : "text-left" }`}>
                                                    {message.time}
                                                </span>
                                            </div>
                                        </div>
                                    </MessageContent>
                                </Message>
                            </MessageScrollerItem>
                        ))}
                    </MessageScrollerContent>
                </MessageScrollerViewport>
                <MessageScrollerButton />
            </MessageScroller>
        </MessageScrollerProvider>
    </div>

      <div className="flex flex-col items-center gap-3 px-4 py-4">
        <button
          type="button"
          className="flex h-14 w-14 items-center justify-center rounded-full border border-[#39212e] bg-[#28131f] text-[#a35b89]"
        >
          <Mic size={24} />
        </button>

        <p className="text-[10px] tracking-[0.2em] text-[#a35b89]">
          TAP TO SPEAK
        </p>
      </div>

      <div className="flex items-center gap-2 border-t border-[#39212e] p-3">
        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="Type a message..."
          className="min-w-0 flex-1 rounded-full border border-[#39212e] bg-[#28131f] px-4 py-3 text-sm text-white outline-none placeholder:text-[#a35b89]"
        />

        <button
          type="button"
          className="flex h-10 w-10 items-center justify-center rounded-full bg-[#28131f] text-[#f472b6]"
        >
          <Send size={18} fill="#c85d96" stroke="#c85d96"/>
        </button>
      </div>

</div>
  )
}

export default BellAI