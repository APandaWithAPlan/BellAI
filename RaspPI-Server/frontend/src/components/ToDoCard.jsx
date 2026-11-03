import { useState } from "react"
import { Card, CardContent } from "./ui/card"
import { Checkbox } from "@/components/ui/checkbox"

function ToDoCard({ task }) {
  const [completed, setCompleted] = useState(false)

  return (
    
    <div className="flex items-center gap-3 rounded-xl border border-[#fbcfe8] bg-white px-4 py-3 last:border-b-0 shadow-lg">

      <Checkbox checked={completed} onCheckedChange={setCompleted} className="rounded border-[#fbcfe8] data-checked:border-[#fbcfe8] data-checked:bg-[#34d399]"/>

      <span className={`text-sm ${ completed ? "text-[#be185d] line-through" : "text-black" }`}>
        {task}
      </span>

    </div>
  )
}

export default ToDoCard