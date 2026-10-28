import { Card, CardContent } from "./ui/card"

function EmailCard({ sender, subject, contents, time }) {
  return (
    <Card className="rounded-xl border border-[#7d5070] bg-[#20151c] p-4 text-white shadow-lg">
      <CardContent className="flex flex-col gap-1 p-0">

        <div className="flex items-start justify-between gap-4">

            <p className="text-lg font-semibold">
                {sender}
            </p>

            <p className="shrink-0 text-xs text-[#a35b89]">
                {time}
            </p>

        </div>

            <p className="text-sm text-[#f472b6]">
              {subject}
            </p>

            <p className="text-xs text-[#a35b89]">
              {contents}
            </p>

      </CardContent>
    </Card>
  )
}

export default EmailCard