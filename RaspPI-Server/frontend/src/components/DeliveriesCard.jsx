import { Card, CardContent } from "./ui/card"
import { Progress } from "@/components/ui/progress"

function EventCard({ sender, subject, due }) {
  return (
    <Card className="rounded-xl border border-[#fbcfe8] bg-white p-4 text-black shadow-lg">
      <CardContent className="p-0">

        <div className="flex items-start justify-between">

            <p className="text-lg font-semibold">
                {sender}
            </p>

            <p className="text-sm text-[#be185d]">
                {due}
            </p>

        </div>

            <p className="text-sm text-[#db2e80]">
                {subject}
            </p>

            <Progress value={progress} className="mt-2 bg-[#39212e] [&_[data-slot=progress-indicator]]:bg-[#34d399]"/>

      </CardContent>
    </Card>
  )
}

export default EventCard