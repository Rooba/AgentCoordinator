defmodule AgentCoordinator.VSCodeToolProvider do
  @moduledoc """
  Provides VS Code Extension API tools as MCP-compatible tools.
  
  This module wraps VS Code's Extension API calls and exposes them as MCP tools
  that can be used by agents through the unified coordination system.
  """

  require Logger
  alias AgentCoordinator.VSCodePermissions

  @doc """
  Returns the list of available VS Code tools with their MCP schemas.
  """
  def get_tools do
    [
      # File Operations
      %{
        "name" => "vscode_read_file",
        "description" => "Read file contents using VS Code's file system API. Only works within workspace folders.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "path" => %{
              "type" => "string",
              "description" => "Relative or absolute path to the file within the workspace"
            },
            "encoding" => %{
              "type" => "string", 
              "description" => "File encoding (default: utf8)",
              "enum" => ["utf8", "utf16le", "base64"]
            }
          },
          "required" => ["path"]
        }
      },
      %{
        "name" => "vscode_write_file",
        "description" => "Write content to a file using VS Code's file system API. Creates directories if needed.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "path" => %{
              "type" => "string",
              "description" => "Relative or absolute path to the file within the workspace"
            },
            "content" => %{
              "type" => "string",
              "description" => "Content to write to the file"
            },
            "encoding" => %{
              "type" => "string",
              "description" => "File encoding (default: utf8)",
              "enum" => ["utf8", "utf16le", "base64"]
            },
            "create_directories" => %{
              "type" => "boolean",
              "description" => "Create parent directories if they don't exist (default: true)"
            }
          },
          "required" => ["path", "content"]
        }
      },
      %{
        "name" => "vscode_create_file",
        "description" => "Create a new file using VS Code's file system API.",
        "inputSchema" => %{
          "type" => "object", 
          "properties" => %{
            "path" => %{
              "type" => "string",
              "description" => "Relative or absolute path for the new file within the workspace"
            },
            "content" => %{
              "type" => "string",
              "description" => "Initial content for the file (default: empty)",
              "default" => ""
            },
            "overwrite" => %{
              "type" => "boolean",
              "description" => "Whether to overwrite if file exists (default: false)"
            }
          },
          "required" => ["path"]
        }
      },
      %{
        "name" => "vscode_delete_file",
        "description" => "Delete a file or directory using VS Code's file system API.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "path" => %{
              "type" => "string", 
              "description" => "Relative or absolute path to the file/directory within the workspace"
            },
            "recursive" => %{
              "type" => "boolean",
              "description" => "Whether to delete directories recursively (default: false)"
            },
            "use_trash" => %{
              "type" => "boolean",
              "description" => "Whether to move to trash instead of permanent deletion (default: true)"
            }
          },
          "required" => ["path"]
        }
      },
      %{
        "name" => "vscode_list_directory",
        "description" => "List contents of a directory using VS Code's file system API.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "path" => %{
              "type" => "string",
              "description" => "Relative or absolute path to the directory within the workspace"
            },
            "include_hidden" => %{
              "type" => "boolean", 
              "description" => "Whether to include hidden files/directories (default: false)"
            }
          },
          "required" => ["path"]
        }
      },
      %{
        "name" => "vscode_get_workspace_folders",
        "description" => "Get list of workspace folders currently open in VS Code.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{}
        }
      },

      # Editor Operations
      %{
        "name" => "vscode_get_active_editor",
        "description" => "Get information about the currently active text editor.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "include_content" => %{
              "type" => "boolean",
              "description" => "Whether to include the full document content (default: false)"
            }
          }
        }
      },
      %{
        "name" => "vscode_set_editor_content",
        "description" => "Set content in the active text editor or a specific file.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "content" => %{
              "type" => "string",
              "description" => "Content to set in the editor"
            },
            "file_path" => %{
              "type" => "string",
              "description" => "Optional: specific file path. If not provided, uses active editor"
            },
            "range" => %{
              "type" => "object",
              "description" => "Optional: specific range to replace",
              "properties" => %{
                "start_line" => %{"type" => "number"},
                "start_character" => %{"type" => "number"},
                "end_line" => %{"type" => "number"},
                "end_character" => %{"type" => "number"}
              }
            },
            "create_if_not_exists" => %{
              "type" => "boolean",
              "description" => "Create file if it doesn't exist (default: false)"
            }
          },
          "required" => ["content"]
        }
      },
      %{
        "name" => "vscode_get_selection",
        "description" => "Get current text selection in the active editor.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "include_content" => %{
              "type" => "boolean",
              "description" => "Whether to include the selected text content (default: true)"
            }
          }
        }
      },
      %{
        "name" => "vscode_set_selection",
        "description" => "Set text selection in the active editor.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "start_line" => %{
              "type" => "number",
              "description" => "Start line number (0-based)"
            },
            "start_character" => %{
              "type" => "number", 
              "description" => "Start character position (0-based)"
            },
            "end_line" => %{
              "type" => "number",
              "description" => "End line number (0-based)"
            },
            "end_character" => %{
              "type" => "number",
              "description" => "End character position (0-based)"
            },
            "reveal" => %{
              "type" => "boolean",
              "description" => "Whether to reveal/scroll to the selection (default: true)"
            }
          },
          "required" => ["start_line", "start_character", "end_line", "end_character"]
        }
      },

      # Command Operations
      %{
        "name" => "vscode_run_command",
        "description" => "Execute a VS Code command. Only whitelisted commands are allowed for security.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "command" => %{
              "type" => "string",
              "description" => "VS Code command to execute"
            },
            "args" => %{
              "type" => "array",
              "description" => "Arguments to pass to the command",
              "items" => %{"type" => "string"}
            }
          },
          "required" => ["command"]
        }
      },

      # User Communication
      %{
        "name" => "vscode_show_message",
        "description" => "Display a message to the user in VS Code.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "message" => %{
              "type" => "string",
              "description" => "Message to display"
            },
            "type" => %{
              "type" => "string",
              "description" => "Message type",
              "enum" => ["info", "warning", "error"]
            },
            "modal" => %{
              "type" => "boolean",
              "description" => "Whether to show as modal dialog (default: false)"
            }
          },
          "required" => ["message"]
        }
      }
    ]
  end

  @doc """
  Handle a VS Code tool call with permission checking and error handling.
  """
  def handle_tool_call(tool_name, args, context) do
    Logger.info("VS Code tool call: #{tool_name} with args: #{inspect(args)}")
    
    # Check permissions
    case VSCodePermissions.check_permission(context, tool_name, args) do
      {:ok, _permission_level} ->
        # Execute the tool
        result = execute_tool(tool_name, args, context)
        
        # Log the operation
        log_tool_operation(tool_name, args, context, result)
        
        result
        
      {:error, reason} ->
        Logger.warning("Permission denied for #{tool_name}: #{reason}")
        {:error, %{"error" => "Permission denied", "reason" => reason}}
    end
  end

  # Private function to execute individual tools
  defp execute_tool(tool_name, args, context) do
    case tool_name do
      "vscode_read_file" -> read_file(args, context)
      "vscode_write_file" -> write_file(args, context) 
      "vscode_create_file" -> create_file(args, context)
      "vscode_delete_file" -> delete_file(args, context)
      "vscode_list_directory" -> list_directory(args, context)
      "vscode_get_workspace_folders" -> get_workspace_folders(args, context)
      "vscode_get_active_editor" -> get_active_editor(args, context)
      "vscode_set_editor_content" -> set_editor_content(args, context)
      "vscode_get_selection" -> get_selection(args, context)
      "vscode_set_selection" -> set_selection(args, context)
      "vscode_run_command" -> run_command(args, context)
      "vscode_show_message" -> show_message(args, context)
      _ -> {:error, %{"error" => "Unknown VS Code tool", "tool" => tool_name}}
    end
  end

  # Tool implementations (these will call VS Code Extension API via JavaScript bridge)
  
  defp read_file(args, _context) do
    # For now, return a placeholder - we'll implement the actual VS Code API bridge
    {:ok, %{
      "content" => "// VS Code file content would be here",
      "path" => args["path"],
      "encoding" => args["encoding"] || "utf8",
      "size" => 42,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }}
  end

  defp write_file(args, _context) do
    {:ok, %{
      "path" => args["path"],
      "bytes_written" => String.length(args["content"]),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }}
  end

  defp create_file(args, _context) do
    {:ok, %{
      "path" => args["path"],
      "created" => true,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }}
  end

  defp delete_file(args, _context) do
    {:ok, %{
      "path" => args["path"],
      "deleted" => true,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }}
  end

  defp list_directory(args, _context) do
    {:ok, %{
      "path" => args["path"],
      "entries" => [
        %{"name" => "file1.txt", "type" => "file", "size" => 123},
        %{"name" => "subdir", "type" => "directory", "size" => nil}
      ]
    }}
  end

  defp get_workspace_folders(_args, _context) do
    {:ok, %{
      "folders" => [
        %{"name" => "agent_coordinator", "uri" => "file:///home/ra/agent_coordinator"}
      ]
    }}
  end

  defp get_active_editor(args, _context) do
    {:ok, %{
      "file_path" => "/home/ra/agent_coordinator/lib/agent_coordinator.ex",
      "language" => "elixir",
      "line_count" => 150,
      "content" => if(args["include_content"], do: "// Editor content here", else: nil),
      "selection" => %{
        "start" => %{"line" => 10, "character" => 5},
        "end" => %{"line" => 10, "character" => 15}
      },
      "cursor_position" => %{"line" => 10, "character" => 15}
    }}
  end

  defp set_editor_content(args, _context) do
    {:ok, %{
      "file_path" => args["file_path"],
      "content_length" => String.length(args["content"]),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }}
  end

  defp get_selection(args, _context) do
    {:ok, %{
      "selection" => %{
        "start" => %{"line" => 5, "character" => 0},
        "end" => %{"line" => 8, "character" => 20}
      },
      "content" => if(args["include_content"], do: "Selected text here", else: nil),
      "is_empty" => false
    }}
  end

  defp set_selection(args, _context) do
    {:ok, %{
      "selection" => %{
        "start" => %{"line" => args["start_line"], "character" => args["start_character"]},
        "end" => %{"line" => args["end_line"], "character" => args["end_character"]}
      },
      "revealed" => args["reveal"] != false
    }}
  end

  defp run_command(args, _context) do
    # This would execute actual VS Code commands
    {:ok, %{
      "command" => args["command"],
      "args" => args["args"] || [],
      "result" => "Command executed successfully",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }}
  end

  defp show_message(args, _context) do
    {:ok, %{
      "message" => args["message"],
      "type" => args["type"] || "info",
      "displayed" => true,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }}
  end

  # Logging function
  defp log_tool_operation(tool_name, args, context, result) do
    Logger.info("VS Code tool operation completed", %{
      tool: tool_name,
      agent_id: context[:agent_id],
      args_summary: inspect(Map.take(args, ["path", "command", "message"])),
      success: match?({:ok, _}, result),
      timestamp: DateTime.utc_now()
    })
  end
end