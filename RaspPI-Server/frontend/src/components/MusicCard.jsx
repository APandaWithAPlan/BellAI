import { Card, CardContent } from "./ui/card"
import { EighthNotes, Pause, SkipForward, SkipBack } from "lucide-react"

function MusicCard({ song, artist, device }) {
  return (
    <Card className="rounded-xl border border-[#7d5070] bg-[#20151c] p-4 text-white shadow-lg">
      <CardContent className="flex items-center justify-between gap-4 p-0">

        <div className="flex min-w-0 items-center gap-4">

          <div className="rounded-lg bg-[#39212e] p-3">
            <EighthNotes size={24} strokeWidth={1.5} className="text-[#d89fbd]"/>
          </div>

          <div className="min-w-0">
            <h3 className="truncate text-lg font-semibold">
              {song}
            </h3>

            <p className="truncate text-sm text-[#a35b89]">
              {artist} · {device}
            </p>
          </div>

        </div>

        <div className="flex shrink-0 items-center gap-3">
          <button type="button">
            <SkipBack size={20} />
          </button>

          <button
            type="button"
            aria-label="Pause"
            className="rounded-full bg-[#7d5070] p-2"
          >
            <Pause size={20} />
          </button>

          <button type="button">
            <SkipForward size={20} />
          </button>
        </div>

      </CardContent>
    </Card>
  )
}

export default MusicCard