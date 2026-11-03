import { Card, CardContent } from "./ui/card"

function EmailCard({ sender, subject, contents, time }) {
  return (
    <Card className="rounded-xl border border-[#fbcfe8] bg-white p-4 text-white shadow-lg">
      <CardContent className="flex flex-col gap-1 p-0">

        <div className="flex items-start justify-between gap-4">

            <p className="text-lg font-semibold text-black">
                {sender}
            </p>

            <p className="shrink-0 text-xs text-[#be185d]">
                {time}
            </p>

        </div>

            <p className="text-sm text-[#db2e80]">
              {subject}
            </p>

            <p className="text-xs text-[#be185d]">
              {contents}
            </p>

      </CardContent>
    </Card>
  )
}

export default EmailCard