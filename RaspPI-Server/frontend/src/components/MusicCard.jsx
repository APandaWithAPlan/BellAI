import { Card, CardContent } from "./ui/card"
import { EighthNotes, Pause, Play, SkipForward, SkipBack } from "lucide-react"
import { toast } from "@/components/ui/toast"
import { useState} from "react";

function MusicCard({ song, artist, device }) {

  const [isPlaying, setIsPlaying] = useState(device.state === "playing");

  useEffect(() => {
    setIsPlaying(device?.state === "playing");
  }, [device?.state]);

  async function controlMusic(action) {

    const response = await fetch("/api/devices/control", {
      method: "POST",
      headers: {
          "Content-Type": "application/json"
      },
      body: JSON.stringify({
          entity_id: device.entity_id,
          domain: "media_player",
          action,
          data: {}
      })
    });

    if (!response.ok) {
      toast.add({
        type: "error",
        description: `Failed to control ${device.entity_id}`
      });

      throw new Error("Failed to control device");
    }

    if (action === "media_play") {
      setIsPlaying(true);
    }
      
    else if (action === "media_pause") {
      setIsPlaying(false);
    }
    
    return response.json();
  }

  return (
    <Card className="rounded-xl border border-[#fbcfe8] bg-white p-4 text-black shadow-lg">
      <CardContent className="flex items-center justify-between gap-4 p-0">

        <div className="flex min-w-0 items-center gap-4">

          <div className="rounded-lg bg-[#fae4ee] p-3">
            <EighthNotes size={24} strokeWidth={1.5} className="text-[#be185d]"/>
          </div>

          <div className="min-w-0">
            <h3 className="truncate text-lg font-semibold">
              {song}
            </h3>

            <p className="truncate text-sm text-[#be185d]">
              {artist} · {device}
            </p>
          </div>

        </div>

        <div className="flex shrink-0 items-center gap-3 text-[#db2777]">
          <button type="button"
            onClick={() => controlMusic("media_previous_track")}
          >
            <SkipBack size={20} />
          </button>

          <button
            type="button"
            className="rounded-full bg-[#db2777] p-2 text-white"
            onClick={() => controlMusic(isPlaying ? "media_pause" : "media_play")}
          >
            {isPlaying ? <Pause fill="white" size={20} /> :<Play fill="white" size={20} />}
          </button>

          <button type="button"
            onClick={() => controlMusic("media_next_track", {})}
          >
            <SkipForward size={20} />
          </button>
        </div>

      </CardContent>
    </Card>
  )
}

export default MusicCard