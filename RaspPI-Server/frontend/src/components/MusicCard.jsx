import { Card, CardContent } from "./ui/card"
import { useDeviceCommand } from "../hooks/useDeviceCommand"
import { EighthNotes, Pause, Play, SkipForward, SkipBack } from "lucide-react"

function MusicCard({ entity_id, device, song, artist, isPlaying }) {
  const { commandDevice } = useDeviceCommand();

  async function controlMusic(action) {
    await commandDevice(entity_id, "media_player", action);
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
              {artist ? `${artist}` : "Idle"} · {device ? `${device}` : "Unknown Device"}
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
            {isPlaying ? <Pause fill="white" size={20} /> : <Play fill="white" size={20} />}
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