{
  title: 'Google Docs',

  custom_action: true,
  custom_action_help: {
    learn_more_url: 'https://developers.google.com/docs/api/reference/rest',
    learn_more_text: 'Google Docs API documentation',
    body: '<p>Build your own Google Docs action with a HTTP request. The request will ' \
      'be authorized with your Google Docs connection.</p>'
  },

  connection: {
    fields: [
      { name: 'auth_type',
        control_type: 'select',
        optional: false,
        extends_schema: true,
        options: [
          %w[OAuth\ 2.0 oauth2],
          %w[Service\ account service_account]
        ] }
    ],
    authorization: {
      type: 'multi',

      selected: lambda do |connection|
        connection['auth_type']
      end,

      options: {
        oauth2: {
          type: 'oauth2',
          fields: [
            {
              name: 'client_id',
              hint: 'You can find your client ID by logging in to your ' \
                "<a href='https://console.developers.google.com/' " \
                "target='_blank'>Google Developers Console</a> account. " \
                "After logging in, click on 'Credentials' to show your " \
                'OAuth 2.0 client IDs. <br> Alternatively, you can create your ' \
                "Oauth 2.0 credentials by clicking on 'Create credentials' => " \
                "'Oauth client ID'. <br> Please use <b>https://www.workato.com/" \
                'oauth/callback</b> for the redirect URI when registering your ' \
                'OAuth client. <br> More information about authentication ' \
                "can be found <a href='https://developers.google.com/identity/" \
                "protocols/OAuth2?hl=en_US' target='_blank'>here</a>.",
              optional: false
            },
            {
              name: 'client_secret',
              hint: 'You can find your client secret by logging in to your ' \
                "<a href='https://console.developers.google.com/' " \
                "target='_blank'>Google Developers Console</a> account. " \
                "After logging in, click on 'Credentials' to show your " \
                'OAuth 2.0 client IDs and select your desired account name. ' \
                '<br> Alternatively, you can create your ' \
                "Oauth 2.0 credentials by clicking on 'Create credentials' => " \
                "'Oauth client ID'. <br> More information about authentication " \
                "can be found <a href='https://developers.google.com/identity/" \
                "protocols/OAuth2?hl=en_US' target='_blank'>here</a>.",
              optional: false,
              control_type: 'password'
            }
          ],
          authorization_url: lambda do |connection|
            scopes = [
              'https://www.googleapis.com/auth/documents',
              'https://www.googleapis.com/auth/drive'
            ].join(' ')
            params = {
              client_id: connection['client_id'],
              response_type: 'code',
              scope: scopes,
              access_type: 'offline',
              include_granted_scopes: 'true',
              prompt: 'consent'
            }.to_param

            "https://accounts.google.com/o/oauth2/auth?#{params}"
          end,
          acquire: lambda do |connection, auth_code|
            response = post('https://accounts.google.com/o/oauth2/token').
                       payload(client_id: connection['client_id'],
                               client_secret: connection['client_secret'],
                               grant_type: 'authorization_code',
                               code: auth_code,
                               redirect_uri: 'https://www.workato.com/oauth/callback').
                       request_format_www_form_urlencoded
            [response, nil, nil]
          end,
          refresh: lambda do |connection, refresh_token|
            post('https://accounts.google.com/o/oauth2/token').
              payload(client_id: connection['client_id'],
                      client_secret: connection['client_secret'],
                      grant_type: 'refresh_token',
                      refresh_token: refresh_token).
              request_format_www_form_urlencoded
          end,
          apply: lambda do |_connection, access_token|
            headers(Authorization: "Bearer #{access_token}")
          end
        },
        service_account: {
          type: 'custom',

          fields: [
            {
              name: 'iss',
              label: 'Service account email',
              control_type: 'email',
              optional: false,
              hint: 'The email address of the service account'
            },
            {
              name: 'private_key', control_type: 'password',
              optional: false, multiline: true,
              hint: 'Copy and paste the private key that came from the downloaded ' \
              'json. Click <a href="https://developers.google.com/identity/' \
              'protocols/oauth2/service-account/" target="_blank">here</a> ' \
              'to learn more about Google Service Accounts.'
            }
          ],

          acquire: lambda do |connection|
            scopes = [
              'https://www.googleapis.com/auth/documents',
              'https://www.googleapis.com/auth/drive'
            ].join(' ')

            jwt_body_claim = {
              iat: now.to_i,
              exp: 1.hour.from_now.to_i,
              aud: 'https://oauth2.googleapis.com/token',
              iss: connection['iss'],
              scope: scopes
            }

            private_key = connection['private_key'].gsub(/\\n/, "\n")
            jwt_token = workato.jwt_encode_rs256(jwt_body_claim, private_key)

            post('https://oauth2.googleapis.com/token').
              payload(grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                      assertion: jwt_token).request_format_www_form_urlencoded
          end,

          refresh_on: [401, 403],

          apply: lambda do |connection|
            headers(Authorization: "Bearer #{connection['access_token']}")
          end
        }
      }
    },
    base_uri: lambda do |_connection|
      'https://docs.googleapis.com/v1/'
    end
  },
  test: lambda do |_connection|
    get('/$discovery/rest?version=v1')
  end,
  methods: {
    make_schema_builder_fields_sticky: lambda do |schema|
      schema.map do |field|
        if field['properties'].present?
          field['properties'] = call('make_schema_builder_fields_sticky',
                                     field['properties'])
        end
        field['sticky'] = true

        field
      end
    end,
    format_schema: lambda do |input|
      input&.map do |field|
        if (props = field[:properties])
          field[:properties] = call('format_schema', props)
        elsif (props = field['properties'])
          field['properties'] = call('format_schema', props)
        end
        if (name = field[:name])
          field[:label] = field[:label].presence || name.labelize
          field[:name] = name.gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
        elsif (name = field['name'])
          field['label'] = field['label'].presence || name.labelize
          field['name'] = name.gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
        end

        field
      end
    end,
    format_payload: lambda do |payload|
      if payload.is_a?(Array)
        payload.map do |array_value|
          call('format_payload', array_value)
        end
      elsif payload.is_a?(Hash)
        payload.each_with_object({}) do |(key, value), hash|
          key = key.gsub(/__\w+?__/) do |string|
            string.gsub(/__/, '').decode_hex.as_utf8
          end
          value = call('format_payload', value) if value.is_a?(Array) || value.is_a?(Hash)
          hash[key] = value
        end
      end
    end,
    format_response: lambda do |response|
      response = response&.compact unless response.is_a?(String) || response
      if response.is_a?(Array)
        response.map do |array_value|
          call('format_response', array_value)
        end
      elsif response.is_a?(Hash)
        response.each_with_object({}) do |(key, value), hash|
          key = key.gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
          value = call('format_response', value) if value.is_a?(Array) || value.is_a?(Hash)
          hash[key] = value
        end
      else
        response
      end
    end,
    get_sample_output: lambda do |input|
      case input['object']
      when 'document'
        {
          title: 'Untitled document',
          body: {
            content: [
              { endIndex: 1,
                sectionBreak: {
                  sectionStyle: {
                    columnSeparatorStyle: 'NONE',
                    contentDirection: 'LEFT_TO_RIGHT',
                    sectionType: 'CONTINUOUS'
                  }
                } }
            ]
          },
          documentStyle: {
            pageNumberStart: 1,
            marginTop: {
              magnitude: 72,
              unit: 'PT'
            },
            marginBottom: {
              magnitude: 72,
              unit: 'PT'
            },
            marginRight: {
              magnitude: 72,
              unit: 'PT'
            },
            marginLeft: {
              magnitude: 72,
              unit: 'PT'
            },
            pageSize: {
              height: {
                magnitude: 792,
                unit: 'PT'
              },
              width: {
                magnitude: 612,
                unit: 'PT'
              }
            },
            marginHeader: {
              magnitude: 36,
              unit: 'PT'
            },
            marginFooter: {
              magnitude: 36,
              unit: 'PT'
            },
            useCustomHeaderFooterMargins: true
          },
          namedStyles: {
            styles: [
              {
                namedStyleType: 'NORMAL_TEXT',
                textStyle: {
                  bold: false,
                  italic: false,
                  underline: false,
                  strikethrough: false,
                  smallCaps: false,
                  fontSize: {
                    magnitude: 11,
                    unit: 'PT'
                  },
                  weightedFontFamily: {
                    fontFamily: 'Arial',
                    weight: 400
                  },
                  baselineOffset: 'NONE'
                },
                paragraphStyle: {
                  namedStyleType: 'NORMAL_TEXT',
                  alignment: 'START',
                  lineSpacing: 115,
                  direction: 'LEFT_TO_RIGHT',
                  spacingMode: 'COLLAPSE_LISTS',
                  spaceAbove: {
                    unit: 'PT'
                  },
                  spaceBelow: {
                    unit: 'PT'
                  },
                  borderBetween: {
                    width: {
                      unit: 'PT'
                    },
                    padding: {
                      unit: 'PT'
                    },
                    dashStyle: 'SOLID'
                  },
                  borderTop: {
                    width: {
                      unit: 'PT'
                    },
                    padding: {
                      unit: 'PT'
                    },
                    dashStyle: 'SOLID'
                  },
                  borderBottom: {
                    width: {
                      unit: 'PT'
                    },
                    padding: {
                      unit: 'PT'
                    },
                    dashStyle: 'SOLID'
                  },
                  borderLeft: {
                    width: {
                      unit: 'PT'
                    },
                    padding: {
                      unit: 'PT'
                    },
                    dashStyle: 'SOLID'
                  },
                  borderRight: {
                    width: {
                      unit: 'PT'
                    },
                    padding: {
                      unit: 'PT'
                    },
                    dashStyle: 'SOLID'
                  },
                  indentFirstLine: {
                    unit: 'PT'
                  },
                  indentStart: {
                    unit: 'PT'
                  },
                  indentEnd: {
                    unit: 'PT'
                  },
                  keepLinesTogether: false,
                  keepWithNext: false,
                  avoidWidowAndOrphan: true
                }
              }
            ]
          },
          revisionId: 'ALm37BVLHTiiD0OLBUsf0fc08b01YKmAFdn92Wast8K5vJ36dn8dRS1XM...',
          suggestionsViewMode: 'SUGGESTIONS_INLINE',
          documentId: '14qyjH2fd11C84UmmrpU9aZQX5ZheusrnMV6vwducg0s'
        }
      end
    end
  },
  object_definitions: {
    custom_action_input: {
      fields: lambda do |_connection, config_fields|
        verb = config_fields['verb']
        input_schema = parse_json(config_fields.dig('input', 'schema') || '[]')
        data_props =
          input_schema.map do |field|
            if config_fields['request_type'] == 'multipart' &&
               field['binary_content'] == 'true'
              field['type'] = 'object'
              field['properties'] = [
                { name: 'file_content', optional: false },
                {
                  name: 'content_type',
                  default: 'text/plain',
                  sticky: true
                },
                { name: 'original_filename', sticky: true }
              ]
            end
            field
          end
        data_props = call('make_schema_builder_fields_sticky', data_props)
        input_data =
          if input_schema.present?
            if input_schema.dig(0, 'type') == 'array' &&
               input_schema.dig(0, 'details', 'fake_array')
              {
                name: 'data',
                type: 'array',
                of: 'object',
                properties: data_props.dig(0, 'properties')
              }
            else
              { name: 'data', type: 'object', properties: data_props }
            end
          end

        [
          {
            name: 'path',
            hint: 'Base URI is <b>' \
            'https://docs.googleapis.com' \
            '</b> - path will be appended to this URI. Use absolute URI to ' \
            'override this base URI.',
            optional: false
          },
          if %w[post put patch].include?(verb)
            {
              name: 'request_type',
              default: 'json',
              sticky: true,
              extends_schema: true,
              control_type: 'select',
              pick_list: [
                ['JSON request body', 'json'],
                ['URL encoded form', 'url_encoded_form'],
                ['Mutipart form', 'multipart'],
                ['Raw request body', 'raw']
              ]
            }
          end,
          {
            name: 'response_type',
            default: 'json',
            sticky: false,
            extends_schema: true,
            control_type: 'select',
            pick_list: [['JSON response', 'json'], ['Raw response', 'raw']]
          },
          if %w[get options delete].include?(verb)
            {
              name: 'input',
              label: 'Request URL parameters',
              sticky: true,
              add_field_label: 'Add URL parameter',
              control_type: 'form-schema-builder',
              type: 'object',
              properties: [
                {
                  name: 'schema',
                  sticky: input_schema.blank?,
                  extends_schema: true
                },
                input_data
              ].compact
            }
          else
            {
              name: 'input',
              label: 'Request body parameters',
              sticky: true,
              type: 'object',
              properties:
                if config_fields['request_type'] == 'raw'
                  [{
                    name: 'data',
                    sticky: true,
                    control_type: 'text-area',
                    type: 'string'
                  }]
                else
                  [
                    {
                      name: 'schema',
                      sticky: input_schema.blank?,
                      extends_schema: true,
                      schema_neutral: true,
                      control_type: 'schema-designer',
                      sample_data_type: 'json_input',
                      custom_properties:
                        if config_fields['request_type'] == 'multipart'
                          [{
                            name: 'binary_content',
                            label: 'File attachment',
                            default: false,
                            optional: true,
                            sticky: true,
                            render_input: 'boolean_conversion',
                            parse_output: 'boolean_conversion',
                            control_type: 'checkbox',
                            type: 'boolean'
                          }]
                        end
                    },
                    input_data
                  ].compact
                end
            }
          end,
          {
            name: 'request_headers',
            sticky: false,
            extends_schema: true,
            control_type: 'key_value',
            empty_list_title: 'Does this HTTP request require headers?',
            empty_list_text: 'Refer to the API documentation and add ' \
            'required headers to this HTTP request',
            item_label: 'Header',
            type: 'array',
            of: 'object',
            properties: [{ name: 'key' }, { name: 'value' }]
          },
          unless config_fields['response_type'] == 'raw'
            {
              name: 'output',
              label: 'Response body',
              sticky: true,
              extends_schema: true,
              schema_neutral: true,
              control_type: 'schema-designer',
              sample_data_type: 'json_input'
            }
          end,
          {
            name: 'response_headers',
            sticky: false,
            extends_schema: true,
            schema_neutral: true,
            control_type: 'schema-designer',
            sample_data_type: 'json_input'
          }
        ].compact
      end
    },
    custom_action_output: {
      fields: lambda do |_connection, config_fields|
        response_body = { name: 'body' }

        [
          if config_fields['response_type'] == 'raw'
            response_body
          elsif (output = config_fields['output'])
            output_schema = call('format_schema', parse_json(output))
            if output_schema.dig(0, 'type') == 'array' &&
               output_schema.dig(0, 'details', 'fake_array')
              response_body[:type] = 'array'
              response_body[:properties] = output_schema.dig(0, 'properties')
            else
              response_body[:type] = 'object'
              response_body[:properties] = output_schema
            end

            response_body
          end,
          if (headers = config_fields['response_headers'])
            header_props = parse_json(headers)&.map do |field|
              if field[:name].present?
                field[:name] = field[:name].gsub(/\W/, '_').downcase
              elsif field['name'].present?
                field['name'] = field['name'].gsub(/\W/, '_').downcase
              end
              field
            end

            { name: 'headers', type: 'object', properties: header_props }
          end
        ].compact
      end
    },
    create_document_input: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [{ name: 'title',
           optional: false },
         { name: 'body',
           hint: 'The content will be formatted as a paragraph by default.',
           optional: false }]
      end
    },
    create_document_from_template_input: {
      fields: lambda do |_connection, config_fields, object_definitions|
        custom_fields = if config_fields['schema_fields'].present?
                          parse_json(config_fields['schema_fields'])
                        else
                          []
                        end

        [{ name: 'id',
           label: 'Document ID',
           optional: false,
           hint: 'Can be found in the document URL. e.g. ' \
                 'https://docs.google.com/document/d/<b>DOCUMENT_ID</b>/edit' },
         { name: 'schema_fields',
           label: 'Template fields',
           sticky: true,
           optional: false,
           extends_schema: true,
           schema_neutral: true,
           hint: 'Please specify the replaceable fields (case-sensitive) from the template ' \
                 'enclose with mustache. e.g.<b> \{\{field_name}}</b>',
           control_type: 'schema-designer',
           sample_data_type: 'json_input' },
         (if custom_fields.present?
            { name: 'fields',
              type: 'object',
              properties: custom_fields }
          end),
         { name: 'text_style',
           type: 'object',
           hint: 'This will apply the same style for <b>all</b> text that is being replaced.',
           properties: [
             { name: 'bold',
               control_type: 'checkbox',
               convert_input: 'boolean_conversion',
               sticky: true,
               toggle_hint: 'Select from list',
               toggle_field: {
                 toggle_hint: 'Enter custom value',
                 name: 'bold',
                 label: 'Bold',
                 type: 'string',
                 control_type: 'text',
                 convert_input: 'boolean_conversion',
                 optional: false,
                 hint: 'Valid values are: true or false.'
               } },
             { name: 'italic',
               control_type: 'checkbox',
               convert_input: 'boolean_conversion',
               sticky: true,
               toggle_hint: 'Select from list',
               toggle_field: {
                 toggle_hint: 'Enter custom value',
                 name: 'italic',
                 label: 'Italic',
                 type: 'string',
                 control_type: 'text',
                 convert_input: 'boolean_conversion',
                 optional: false,
                 hint: 'Valid values are: true or false.'
               } },
             { name: 'underline',
               control_type: 'checkbox',
               convert_input: 'boolean_conversion',
               sticky: true,
               toggle_hint: 'Select from list',
               toggle_field: {
                 toggle_hint: 'Enter custom value',
                 name: 'underline',
                 label: 'Underline',
                 type: 'string',
                 control_type: 'text',
                 convert_input: 'boolean_conversion',
                 optional: false,
                 hint: 'Valid values are: true or false.'
               } },
             { name: 'strikethrough',
               control_type: 'checkbox',
               convert_input: 'boolean_conversion',
               sticky: true,
               toggle_hint: 'Select from list',
               toggle_field: {
                 toggle_hint: 'Enter custom value',
                 name: 'strikethrough',
                 label: 'Strikethrough',
                 type: 'string',
                 control_type: 'text',
                 convert_input: 'boolean_conversion',
                 optional: false,
                 hint: 'Valid values are: true or false.'
               } },
             { name: 'smallCaps',
               control_type: 'checkbox',
               convert_input: 'boolean_conversion',
               sticky: true,
               toggle_hint: 'Select from list',
               toggle_field: {
                 toggle_hint: 'Enter custom value',
                 name: 'smallCaps',
                 label: 'Small caps',
                 type: 'string',
                 control_type: 'text',
                 convert_input: 'boolean_conversion',
                 optional: false,
                 hint: 'Valid values are: true or false.'
               } },
             { name: 'backgroundColor',
               type: 'object',
               properties: object_definitions['color_schema'] },
             { name: 'foregroundColor',
               type: 'object',
               properties: object_definitions['color_schema'] },
             { name: 'fontSize',
               type: 'object',
               properties: [
                 { name: 'magnitude',
                   control_type: 'number',
                   convert_input: 'float_conversion' },
                 { name: 'unit',
                   control_type: 'select',
                   pick_list: [
                     %w[Unspecified UNIT_UNSPECIFIED],
                     %w[Point PT]
                   ],
                   toggle_hint: 'Select from list',
                   toggle_field: {
                     toggle_hint: 'Enter custom value',
                     name: 'unit',
                     label: 'Unit',
                     type: 'string',
                     control_type: 'text',
                     optional: true,
                     hint: 'Valid values are: UNIT_UNSPECIFIED or PT.'
                   } }
               ] },
             { name: 'weightedFontFamily',
               type: 'object',
               properties: [
                 { name: 'fontFamily',
                   hint: 'The font family of the text. If the font name is unrecognized, ' \
                         'the text is rendered in Arial.' },
                 { name: 'weight',
                   control_type: 'integer',
                   convert_input: 'integer_conversion' }
               ] },
             { name: 'baselineOffset',
               control_type: 'select',
               pick_list: [
                 %w[Unspecified BASELINE_OFFSET_UNSPECIFIED],
                 %w[None NONE],
                 %w[Superscript SUPERSCRIPT],
                 %w[Subscript SUBSCRIPT]
               ],
               toggle_hint: 'Select from list',
               toggle_field: {
                 toggle_hint: 'Enter custom value',
                 name: 'baselineOffset',
                 label: 'Baseline offset',
                 type: 'string',
                 control_type: 'text',
                 optional: true,
                 hint: 'Valid values are: BASELINE_OFFSET_UNSPECIFIED, NONE, ' \
                       'SUPERSCRIPT or SUBSCRIPT.'
               } },
             { name: 'link',
               type: 'object',
               properties: [
                 { name: 'url', label: 'URL', sticky: true,
                   hint: 'An external URL.' },
                 { name: 'tabId', sticky: true,
                   hint: 'The ID of a tab in this document.' },
                 { name: 'bookmark',
                   type: 'object',
                   properties: [
                     { name: 'id', label: 'Bookmark ID' },
                     { name: 'tabId',
                       hint: 'The ID of the tab containing this bookmark.' }
                   ] },
                 { name: 'heading',
                   type: 'object',
                   properties: [
                     { name: 'id', label: 'Heading ID' },
                     { name: 'tabId',
                       hint: 'The Id of the tab containing this heading.' }
                   ] },
                 { name: 'bookmarkId',
                   hint: 'he ID of a bookmark in this document.' },
                 { name: 'headingId',
                   hint: 'The ID of a heading in this document.' }
               ] }
           ] }].compact
      end
    },
    create_document_from_template_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        object_definitions['document']
      end
    },
    color_schema: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'color',
            type: 'object',
            properties: [
              { name: 'rgbColor',
                type: 'object',
                properties: [
                  { name: 'red',
                    control_type: 'integer',
                    convert_input: 'integer_conversion' },
                  { name: 'green',
                    control_type: 'integer',
                    convert_input: 'integer_conversion' },
                  { name: 'blue',
                    control_type: 'integer',
                    convert_input: 'integer_conversion' }
                ] }
            ] }
        ]
      end
    },
    replace_all_text: {
      fields: lambda do
        [
          { name: 'replaceAllText', optional: false, type: 'object',
            properties: [
              { name: 'replaceText',
                optional: false,
                label: 'Replace with' },
              { name: 'containsText', type: 'object', optional: false, label: 'Find',
                properties: [
                  { name: 'text',
                    optional: false,
                    label: 'Find text' },
                  { name: 'matchCase',
                    type: 'boolean',
                    control_type: 'checkbox',
                    render_input: 'boolean_conversion',
                    parse_output: 'boolean_conversion',
                    optional: false,
                    label: 'Match case',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      toggle_hint: 'Enter custom value',
                      name: 'matchCase',
                      type: 'boolean',
                      control_type: 'text',
                      render_input: 'boolean_conversion',
                      parse_output: 'boolean_conversion',
                      label: 'Match case',
                      optional: false,
                      hint: 'Valid values are: true or false.'
                    } }
                ] }
            ] }
        ]
      end
    },
    document: {
      fields: lambda do
        [
          { name: 'documentId' },
          { name: 'title' },
          { name: 'body', type: 'object',
            properties: [
              { name: 'content', type: 'array', of: 'object',
                properties: [
                  { name: 'startIndex',
                    control_type: 'number',
                    type: 'number' },
                  { name: 'endIndex',
                    control_type: 'number',
                    type: 'number' },
                  { name: 'sectionBreak', type: 'object',
                    properties: [
                      { name: 'suggestedInsertionIds', label: 'Suggested insertion IDs',
                        type: 'array', of: 'string' },
                      { name: 'suggestedDeletionIds', label: 'Suggested deletion IDs',
                        type: 'array', of: 'string' },
                      { name: 'sectionStyle', type: 'object',
                        properties: [
                          { name: 'columnProperties', type: 'array', of: 'object', properties: [
                            { name: 'width', type: 'object',
                              properties: [
                                { name: 'magnitude', control_type: 'number', type: 'number' },
                                { name: 'unit' }
                              ] },
                            { name: 'paddingEnd', type: 'object',
                              properties: [
                                { name: 'magnitude', control_type: 'number', type: 'number' },
                                { name: 'unit' }
                              ] }
                          ] },
                          { name: 'columnSeparatorStyle' },
                          { name: 'contentDirection' },
                          { name: 'sectionType' },
                          { name: 'marginTop', type: 'object',
                            properties: [
                              { name: 'magnitude', control_type: 'number', type: 'number' },
                              { name: 'unit' }
                            ] },
                          { name: 'marginBottom', type: 'object',
                            properties: [
                              { name: 'magnitude', control_type: 'number', type: 'number' },
                              { name: 'unit' }
                            ] },
                          { name: 'marginRight', type: 'object',
                            properties: [
                              { name: 'magnitude', control_type: 'number', type: 'number' },
                              { name: 'unit' }
                            ] },
                          { name: 'marginLeft', type: 'object',
                            properties: [
                              { name: 'magnitude', control_type: 'number', type: 'number' },
                              { name: 'unit' }
                            ] },
                          { name: 'marginHeader', type: 'object',
                            properties: [
                              { name: 'magnitude', control_type: 'number', type: 'number' },
                              { name: 'unit' }
                            ] },
                          { name: 'marginFooter', type: 'object',
                            properties: [
                              { name: 'magnitude', control_type: 'number', type: 'number' },
                              { name: 'unit' }
                            ] },
                          { name: 'defaultHeaderId' },
                          { name: 'defaultFooterId' },
                          { name: 'firstPageHeaderId' },
                          { name: 'firstPageFooterId' },
                          { name: 'evenPageHeaderId' },
                          { name: 'evenPageFooterId' },
                          { name: 'useFirstPageHeaderFooter' },
                          { name: 'pageNumberStart' }
                        ] }
                    ] },
                  { name: 'paragraph', type: 'object', properties: [
                    { name: 'elements', type: 'array', of: 'object', properties: [
                      { name: 'startIndex', control_type: 'number', type: 'number' },
                      { name: 'endIndex', control_type: 'number', type: 'number' },
                      { name: 'textRun', type: 'object', properties: [
                        { name: 'content' },
                        { name: 'suggestedInsertionIds', label: 'Suggested insertion IDs',
                          type: 'array', of: 'string' },
                        { name: 'suggestedDeletionIds', label: 'Suggested deletion IDs',
                          type: 'array', of: 'string' },
                        { name: 'textStyle', type: 'object', properties: [
                          { name: 'bold', type: 'boolean' },
                          { name: 'italic', type: 'boolean' },
                          { name: 'underline', type: 'boolean' },
                          { name: 'strikethrough', type: 'boolean' },
                          { name: 'smallCaps', type: 'boolean' },
                          { name: 'backgroundColor', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'foregroundColor', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'fontSize', type: 'object',
                            properties: [
                              { name: 'magnitude', control_type: 'number', type: 'number' },
                              { name: 'unit' }
                            ] },
                          { name: 'weightedFontFamily', type: 'object',
                            properties: [
                              { name: 'fontFamily', control_type: 'number', type: 'number' },
                              { name: 'weight' }
                            ] },
                          { name: 'baselineOffset' },
                          { name: 'link', type: 'object', properties: [
                            { name: 'url' },
                            { name: 'bookmarkId' },
                            { name: 'headingId' }
                          ] }
                        ] }
                      ] },
                      { name: 'autoText', type: 'object', properties: [
                        { name: 'suggestedInsertionIds', label: 'Suggested insertion IDs',
                          type: 'array', of: 'string' },
                        { name: 'suggestedDeletionIds', label: 'Suggested deletion IDs',
                          type: 'array', of: 'string' },
                        { name: 'textStyle', type: 'object', properties: [
                          { name: 'bold', type: 'boolean' },
                          { name: 'italic', type: 'boolean' },
                          { name: 'underline', type: 'boolean' },
                          { name: 'strikethrough', type: 'boolean' },
                          { name: 'smallCaps', type: 'boolean' },
                          { name: 'backgroundColor', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'foregroundColor', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'fontSize', type: 'object',
                            properties: [
                              { name: 'magnitude', control_type: 'number', type: 'number' },
                              { name: 'unit' }
                            ] },
                          { name: 'weightedFontFamily', type: 'object',
                            properties: [
                              { name: 'fontFamily', control_type: 'number', type: 'number' },
                              { name: 'weight' }
                            ] },
                          { name: 'baselineOffset' },
                          { name: 'link', type: 'object', properties: [
                            { name: 'url' },
                            { name: 'bookmarkId' },
                            { name: 'headingId' }
                          ] }
                        ] }
                      ] },
                      { name: 'pageBreak', type: 'object', properties: [
                        { name: 'suggestedInsertionIds', label: 'Suggested insertion IDs',
                          type: 'array', of: 'string' },
                        { name: 'suggestedDeletionIds', label: 'Suggested deletion IDs',
                          type: 'array', of: 'string' },
                        { name: 'textStyle', type: 'object', properties: [
                          { name: 'bold', type: 'boolean' },
                          { name: 'italic', type: 'boolean' },
                          { name: 'underline', type: 'boolean' },
                          { name: 'strikethrough', type: 'boolean' },
                          { name: 'smallCaps', type: 'boolean' },
                          { name: 'backgroundColor', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'foregroundColor', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'fontSize', type: 'object',
                            properties: [
                              { name: 'magnitude', control_type: 'number', type: 'number' },
                              { name: 'unit' }
                            ] },
                          { name: 'weightedFontFamily', type: 'object',
                            properties: [
                              { name: 'fontFamily', control_type: 'number', type: 'number' },
                              { name: 'weight' }
                            ] },
                          { name: 'baselineOffset' },
                          { name: 'link', type: 'object', properties: [
                            { name: 'url' },
                            { name: 'bookmarkId' },
                            { name: 'headingId' }
                          ] }
                        ] }
                      ] },
                      { name: 'columnBreak', type: 'object', properties: [
                        { name: 'suggestedInsertionIds', label: 'Suggested insertion IDs',
                          type: 'array', of: 'string' },
                        { name: 'suggestedDeletionIds', label: 'Suggested deletion IDs',
                          type: 'array', of: 'string' },
                        { name: 'textStyle', type: 'object', properties: [
                          { name: 'bold', type: 'boolean' },
                          { name: 'italic', type: 'boolean' },
                          { name: 'underline', type: 'boolean' },
                          { name: 'strikethrough', type: 'boolean' },
                          { name: 'smallCaps', type: 'boolean' },
                          { name: 'backgroundColor', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'foregroundColor', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'fontSize', type: 'object',
                            properties: [
                              { name: 'magnitude', control_type: 'number', type: 'number' },
                              { name: 'unit' }
                            ] },
                          { name: 'weightedFontFamily', type: 'object',
                            properties: [
                              { name: 'fontFamily', control_type: 'number', type: 'number' },
                              { name: 'weight' }
                            ] },
                          { name: 'baselineOffset' },
                          { name: 'link', type: 'object', properties: [
                            { name: 'url' },
                            { name: 'bookmarkId' },
                            { name: 'headingId' }
                          ] }
                        ] }
                      ] },
                      { name: 'footnoteReference', type: 'object', properties: [
                        { name: 'footnoteId' },
                        { name: 'footnoteNumber' },
                        { name: 'suggestedInsertionIds', label: 'Suggested insertion IDs',
                          type: 'array', of: 'string' },
                        { name: 'suggestedDeletionIds', label: 'Suggested deletion IDs',
                          type: 'array', of: 'string' },
                        { name: 'textStyle', type: 'object', properties: [
                          { name: 'bold', type: 'boolean' },
                          { name: 'italic', type: 'boolean' },
                          { name: 'underline', type: 'boolean' },
                          { name: 'strikethrough', type: 'boolean' },
                          { name: 'smallCaps', type: 'boolean' },
                          { name: 'backgroundColor', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'foregroundColor', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'fontSize', type: 'object',
                            properties: [
                              { name: 'magnitude', control_type: 'number', type: 'number' },
                              { name: 'unit' }
                            ] },
                          { name: 'weightedFontFamily', type: 'object',
                            properties: [
                              { name: 'fontFamily', control_type: 'number', type: 'number' },
                              { name: 'weight' }
                            ] },
                          { name: 'baselineOffset' },
                          { name: 'link', type: 'object', properties: [
                            { name: 'url' },
                            { name: 'bookmarkId' },
                            { name: 'headingId' }
                          ] }
                        ] }
                      ] },
                      { name: 'horizontalRule', type: 'object', properties: [
                        { name: 'suggestedInsertionIds', label: 'Suggested insertion IDs',
                          type: 'array', of: 'string' },
                        { name: 'suggestedDeletionIds', label: 'Suggested deletion IDs',
                          type: 'array', of: 'string' },
                        { name: 'textStyle', type: 'object', properties: [
                          { name: 'bold', type: 'boolean' },
                          { name: 'italic', type: 'boolean' },
                          { name: 'underline', type: 'boolean' },
                          { name: 'strikethrough', type: 'boolean' },
                          { name: 'smallCaps', type: 'boolean' },
                          { name: 'backgroundColor', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'foregroundColor', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'fontSize', type: 'object',
                            properties: [
                              { name: 'magnitude', control_type: 'number', type: 'number' },
                              { name: 'unit' }
                            ] },
                          { name: 'weightedFontFamily', type: 'object',
                            properties: [
                              { name: 'fontFamily', control_type: 'number', type: 'number' },
                              { name: 'weight' }
                            ] },
                          { name: 'baselineOffset' },
                          { name: 'link', type: 'object', properties: [
                            { name: 'url' },
                            { name: 'bookmarkId' },
                            { name: 'headingId' }
                          ] }
                        ] }
                      ] },
                      { name: 'equation', type: 'object', properties: [
                        { name: 'suggestedInsertionIds', label: 'Suggested insertion IDs',
                          type: 'array', of: 'string' },
                        { name: 'suggestedDeletionIds', label: 'Suggested deletion IDs',
                          type: 'array', of: 'string' }
                      ] },
                      { name: 'inlineObjectElement', type: 'object', properties: [
                        { name: 'inlineObjectId' },
                        { name: 'suggestedInsertionIds', label: 'Suggested insertion IDs',
                          type: 'array', of: 'string' },
                        { name: 'suggestedDeletionIds', label: 'Suggested deletion IDs',
                          type: 'array', of: 'string' },
                        { name: 'textStyle', type: 'object', properties: [
                          { name: 'bold', type: 'boolean' },
                          { name: 'italic', type: 'boolean' },
                          { name: 'underline', type: 'boolean' },
                          { name: 'strikethrough', type: 'boolean' },
                          { name: 'smallCaps', type: 'boolean' },
                          { name: 'backgroundColor', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'foregroundColor', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'fontSize', type: 'object',
                            properties: [
                              { name: 'magnitude', control_type: 'number', type: 'number' },
                              { name: 'unit' }
                            ] },
                          { name: 'weightedFontFamily', type: 'object',
                            properties: [
                              { name: 'fontFamily', control_type: 'number', type: 'number' },
                              { name: 'weight' }
                            ] },
                          { name: 'baselineOffset' },
                          { name: 'link', type: 'object', properties: [
                            { name: 'url' },
                            { name: 'bookmarkId' },
                            { name: 'headingId' }
                          ] }
                        ] }
                      ] },
                      { name: 'person', type: 'object', properties: [
                        { name: 'personId' },
                        { name: 'suggestedInsertionIds', label: 'Suggested insertion IDs',
                          type: 'array', of: 'string' },
                        { name: 'suggestedDeletionIds', label: 'Suggested deletion IDs',
                          type: 'array', of: 'string' },
                        { name: 'textStyle', type: 'object', properties: [
                          { name: 'bold', type: 'boolean' },
                          { name: 'italic', type: 'boolean' },
                          { name: 'underline', type: 'boolean' },
                          { name: 'strikethrough', type: 'boolean' },
                          { name: 'smallCaps', type: 'boolean' },
                          { name: 'backgroundColor', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'foregroundColor', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'fontSize', type: 'object',
                            properties: [
                              { name: 'magnitude', control_type: 'number', type: 'number' },
                              { name: 'unit' }
                            ] },
                          { name: 'weightedFontFamily', type: 'object',
                            properties: [
                              { name: 'fontFamily', control_type: 'number', type: 'number' },
                              { name: 'weight' }
                            ] },
                          { name: 'baselineOffset' },
                          { name: 'link', type: 'object', properties: [
                            { name: 'url' },
                            { name: 'bookmarkId' },
                            { name: 'headingId' }
                          ] }
                        ] },
                        { name: 'personProperties', type: 'object', properties: [
                          { name: 'name' },
                          { name: 'email' }
                        ] }
                      ] },
                      { name: 'richLink', type: 'object', properties: [
                        { name: 'richLinkId' },
                        { name: 'suggestedInsertionIds', label: 'Suggested insertion IDs',
                          type: 'array', of: 'string' },
                        { name: 'suggestedDeletionIds', label: 'Suggested deletion IDs',
                          type: 'array', of: 'string' },
                        { name: 'textStyle', type: 'object', properties: [
                          { name: 'bold', type: 'boolean' },
                          { name: 'italic', type: 'boolean' },
                          { name: 'underline', type: 'boolean' },
                          { name: 'strikethrough', type: 'boolean' },
                          { name: 'smallCaps', type: 'boolean' },
                          { name: 'backgroundColor', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'foregroundColor', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'fontSize', type: 'object',
                            properties: [
                              { name: 'magnitude', control_type: 'number', type: 'number' },
                              { name: 'unit' }
                            ] },
                          { name: 'weightedFontFamily', type: 'object',
                            properties: [
                              { name: 'fontFamily', control_type: 'number', type: 'number' },
                              { name: 'weight' }
                            ] },
                          { name: 'baselineOffset' },
                          { name: 'link', type: 'object', properties: [
                            { name: 'url' },
                            { name: 'bookmarkId' },
                            { name: 'headingId' }
                          ] }
                        ] },
                        { name: 'richLinkProperties', type: 'object', properties: [
                          { name: 'title' },
                          { name: 'uri' },
                          { name: 'mimeType' }
                        ] }
                      ] }
                    ] },
                    { name: 'paragraphStyle', type: 'object',
                      properties: [
                        { name: 'namedStyleType' },
                        { name: 'alignment' },
                        { name: 'lineSpacing', control_type: 'number', type: 'number' },
                        { name: 'direction' },
                        { name: 'spacingMode' },
                        { name: 'spaceAbove', type: 'object', properties: [
                          { name: 'unit' }
                        ] },
                        { name: 'spaceBelow', type: 'object', properties: [
                          { name: 'unit' }
                        ] },
                        { name: 'borderBetween', type: 'object',
                          properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] },
                            { name: 'width', type: 'object', properties: [
                              { name: 'unit' }
                            ] },
                            { name: 'padding', type: 'object', properties: [
                              { name: 'unit' }
                            ] },
                            { name: 'dashStyle' }
                          ] },
                        { name: 'borderTop', type: 'object',
                          properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] },
                            { name: 'width', type: 'object', properties: [
                              { name: 'unit' }
                            ] },
                            { name: 'padding', type: 'object', properties: [
                              { name: 'unit' }
                            ] },
                            { name: 'dashStyle' }
                          ] },
                        { name: 'borderBottom', type: 'object',
                          properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] },
                            { name: 'width', type: 'object', properties: [
                              { name: 'unit' }
                            ] },
                            { name: 'padding', type: 'object', properties: [
                              { name: 'unit' }
                            ] },
                            { name: 'dashStyle' }
                          ] },
                        { name: 'borderLeft', type: 'object',
                          properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] },
                            { name: 'width', type: 'object', properties: [
                              { name: 'unit' }
                            ] },
                            { name: 'padding', type: 'object', properties: [
                              { name: 'unit' }
                            ] },
                            { name: 'dashStyle' }
                          ] },
                        { name: 'borderRight', type: 'object',
                          properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] },
                            { name: 'width', type: 'object', properties: [
                              { name: 'unit' }
                            ] },
                            { name: 'padding', type: 'object', properties: [
                              { name: 'unit' }
                            ] },
                            { name: 'dashStyle' }
                          ] },
                        { name: 'indentFirstLine', type: 'object', properties: [
                          { name: 'unit' }
                        ] },
                        { name: 'indentStart', type: 'object', properties: [
                          { name: 'unit' }
                        ] },
                        { name: 'indentEnd', type: 'object', properties: [
                          { name: 'unit' }
                        ] },
                        { name: 'keepLinesTogether', type: 'boolean' },
                        { name: 'keepWithNext', type: 'boolean' },
                        { name: 'avoidWidowAndOrphan', type: 'boolean' },
                        { name: 'shading', type: 'object',
                          properties: [
                            { name: 'backgroundColor', type: 'object',
                              properties: [
                                { name: 'color', type: 'object', properties: [
                                  { name: 'rgbColor', type: 'object', properties: [
                                    { name: 'red' },
                                    { name: 'green' },
                                    { name: 'blue' }
                                  ] }
                                ] }
                              ] }
                          ] }
                      ] },
                    { name: 'bullet', type: 'object', properties: [
                      { name: 'listId' },
                      { name: 'nestingLevel', type: 'integer', control_type: 'integer' },
                      { name: 'textStyle', type: 'object', properties: [
                        { name: 'bold', type: 'boolean' },
                        { name: 'italic', type: 'boolean' },
                        { name: 'underline', type: 'boolean' },
                        { name: 'strikethrough', type: 'boolean' },
                        { name: 'smallCaps', type: 'boolean' },
                        { name: 'backgroundColor', type: 'object', properties: [
                          { name: 'color', type: 'object', properties: [
                            { name: 'rgbColor', type: 'object', properties: [
                              { name: 'red' },
                              { name: 'green' },
                              { name: 'blue' }
                            ] }
                          ] }
                        ] },
                        { name: 'foregroundColor',
                          type: 'object',
                          properties: [
                            { name: 'color',
                              type: 'object',
                              properties: [
                                { name: 'rgbColor', type: 'object', properties: [
                                  { name: 'red' },
                                  { name: 'green' },
                                  { name: 'blue' }
                                ] }
                              ] }
                          ] },
                        { name: 'fontSize', type: 'object',
                          properties: [
                            { name: 'magnitude', control_type: 'number', type: 'number' },
                            { name: 'unit' }
                          ] },
                        { name: 'weightedFontFamily', type: 'object',
                          properties: [
                            { name: 'fontFamily', control_type: 'number', type: 'number' },
                            { name: 'weight' }
                          ] },
                        { name: 'baselineOffset' },
                        { name: 'link', type: 'object', properties: [
                          { name: 'url' },
                          { name: 'bookmarkId' },
                          { name: 'headingId' }
                        ] }
                      ] }
                    ] },
                    { name: 'positionedObjectIds', label: 'Positioned object IDs' }
                  ] },
                  { name: 'table', type: 'object', properties: [
                    { name: 'rows', type: 'integer', control_type: 'integer' },
                    { name: 'columns', type: 'integer', control_type: 'integer' },
                    { name: 'tableRows', type: 'array', of: 'object', properties: [
                      { name: 'startIndex', type: 'integer', control_type: 'integer' },
                      { name: 'endIndex', type: 'integer', control_type: 'integer' },
                      { name: 'tableCells', type: 'array', of: 'object', properties: [
                        { name: 'startIndex', type: 'integer', control_type: 'integer' },
                        { name: 'endIndex', type: 'integer', control_type: 'integer' },
                        { name: 'content', type: 'array', of: 'string' }, # TODO
                        { name: 'tableCellStyle', type: 'object', properties: [
                          { name: 'rowSpan', type: 'integer', control_type: 'integer' },
                          { name: 'columnSpan', type: 'integer', control_type: 'integer' },
                          { name: 'backgroundColor', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'borderLeft', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'color', type: 'object', properties: [
                                { name: 'rgbColor', type: 'object', properties: [
                                  { name: 'red' },
                                  { name: 'green' },
                                  { name: 'blue' }
                                ] }
                              ] }
                            ] },
                            { name: 'width', type: 'object', properties: [
                              { name: 'unit' }
                            ] },
                            { name: 'padding', type: 'object', properties: [
                              { name: 'unit' }
                            ] },
                            { name: 'dashStyle' }
                          ] },
                          { name: 'borderBottom', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'color', type: 'object', properties: [
                                { name: 'rgbColor', type: 'object', properties: [
                                  { name: 'red' },
                                  { name: 'green' },
                                  { name: 'blue' }
                                ] }
                              ] }
                            ] },
                            { name: 'width', type: 'object', properties: [
                              { name: 'unit' }
                            ] },
                            { name: 'padding', type: 'object', properties: [
                              { name: 'unit' }
                            ] },
                            { name: 'dashStyle' }
                          ] },
                          { name: 'borderRight', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'color', type: 'object', properties: [
                                { name: 'rgbColor', type: 'object', properties: [
                                  { name: 'red' },
                                  { name: 'green' },
                                  { name: 'blue' }
                                ] }
                              ] }
                            ] },
                            { name: 'width', type: 'object', properties: [
                              { name: 'unit' }
                            ] },
                            { name: 'padding', type: 'object', properties: [
                              { name: 'unit' }
                            ] },
                            { name: 'dashStyle' }
                          ] },
                          { name: 'borderTop', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'color', type: 'object', properties: [
                                { name: 'rgbColor', type: 'object', properties: [
                                  { name: 'red' },
                                  { name: 'green' },
                                  { name: 'blue' }
                                ] }
                              ] }
                            ] },
                            { name: 'width', type: 'object', properties: [
                              { name: 'unit' }
                            ] },
                            { name: 'padding', type: 'object', properties: [
                              { name: 'unit' }
                            ] },
                            { name: 'dashStyle' }
                          ] },
                          { name: 'paddingLeft', type: 'object',
                            properties: [
                              { name: 'magnitude', control_type: 'number', type: 'number' },
                              { name: 'unit' }
                            ] },
                          { name: 'paddingRight', type: 'object',
                            properties: [
                              { name: 'magnitude', control_type: 'number', type: 'number' },
                              { name: 'unit' }
                            ] },
                          { name: 'paddingTop', type: 'object',
                            properties: [
                              { name: 'magnitude', control_type: 'number', type: 'number' },
                              { name: 'unit' }
                            ] },
                          { name: 'paddingBottom', type: 'object',
                            properties: [
                              { name: 'magnitude', control_type: 'number', type: 'number' },
                              { name: 'unit' }
                            ] },
                          { name: 'contentAlignment' }
                        ] },
                        { name: 'suggestedInsertionIds', label: 'Suggested insertion IDs',
                          type: 'array', of: 'string' },
                        { name: 'suggestedDeletionIds', label: 'Suggested deletion IDs',
                          type: 'array', of: 'string' }
                      ] },
                      { name: 'suggestedInsertionIds', label: 'Suggested insertion IDs',
                        type: 'array', of: 'string' },
                      { name: 'suggestedDeletionIds', label: 'Suggested deletion IDs',
                        type: 'array', of: 'string' },
                      { name: 'tableRowStyle', type: 'object', properties: [
                        { name: 'minRowHeight', type: 'object',
                          properties: [
                            { name: 'magnitude', control_type: 'number', type: 'number' },
                            { name: 'unit' }
                          ] }
                      ] }
                    ] },
                    { name: 'suggestedInsertionIds', label: 'Suggested insertion IDs',
                      type: 'array', of: 'string' },
                    { name: 'suggestedDeletionIds', label: 'Suggested deletion IDs',
                      type: 'array', of: 'string' },
                    { name: 'tableStyle', type: 'object', properties: [
                      { name: 'tableColumnProperties', type: 'array', of: 'object', properties: [
                        { name: 'widthType' },
                        { name: 'width', type: 'object',
                          properties: [
                            { name: 'magnitude', control_type: 'number', type: 'number' },
                            { name: 'unit' }
                          ] }
                      ] }
                    ] }
                  ] },
                  { name: 'tableOfContents', type: 'object', properties: [
                    { name: 'content', type: 'array', of: 'string' },
                    { name: 'suggestedInsertionIds', label: 'Suggested insertion IDs',
                      type: 'array', of: 'string' },
                    { name: 'suggestedDeletionIds', label: 'Suggested deletion IDs',
                      type: 'array', of: 'string' }
                  ] }
                ] }
            ] },
          { name: 'documentStyle', type: 'object',
            properties: [
              { name: 'background', type: 'object', properties: [
                { name: 'color', type: 'object', properties: [
                  { name: 'rgbColor', type: 'object', properties: [
                    { name: 'red' },
                    { name: 'green' },
                    { name: 'blue' }
                  ] }
                ] }
              ] },
              { name: 'pageNumberStart', control_type: 'number', type: 'number' },
              { name: 'marginTop', type: 'object',
                properties: [
                  { name: 'magnitude', control_type: 'number', type: 'number' },
                  { name: 'unit' }
                ] },
              { name: 'marginBottom', type: 'object',
                properties: [
                  { name: 'magnitude', control_type: 'number', type: 'number' },
                  { name: 'unit' }
                ] },
              { name: 'marginRight', type: 'object',
                properties: [
                  { name: 'magnitude', control_type: 'number', type: 'number' },
                  { name: 'unit' }
                ] },
              { name: 'marginLeft', type: 'object',
                properties: [
                  { name: 'magnitude', control_type: 'number', type: 'number' },
                  { name: 'unit' }
                ] },
              { name: 'pageSize', type: 'object',
                properties: [
                  { name: 'height', type: 'object',
                    properties: [
                      { name: 'magnitude', control_type: 'number', type: 'number' },
                      { name: 'unit' }
                    ] },
                  { name: 'width', type: 'object',
                    properties: [
                      { name: 'magnitude', control_type: 'number', type: 'number' },
                      { name: 'unit' }
                    ] }
                ] },
              { name: 'marginHeader', type: 'object',
                properties: [
                  { name: 'magnitude', control_type: 'number', type: 'number' },
                  { name: 'unit' }
                ] },
              { name: 'marginFooter', type: 'object',
                properties: [
                  { name: 'magnitude', control_type: 'number', type: 'number' },
                  { name: 'unit' }
                ] },
              { name: 'useCustomHeaderFooterMargins', type: 'boolean' }
            ] },
          { name: 'namedStyles', type: 'object',
            properties: [
              {
                name: 'styles', type: 'array', of: 'object',
                properties: [
                  { name: 'headingId' },
                  { name: 'namedStyleType' },
                  { name: 'textStyle', type: 'object',
                    properties: [
                      { name: 'bold', type: 'boolean' },
                      { name: 'italic', type: 'boolean' },
                      { name: 'underline', type: 'boolean' },
                      { name: 'strikethrough', type: 'boolean' },
                      { name: 'smallCaps', type: 'boolean' },
                      { name: 'backgroundColor', type: 'object', properties: [
                        { name: 'color', type: 'object', properties: [
                          { name: 'rgbColor', type: 'object', properties: [
                            { name: 'red' },
                            { name: 'green' },
                            { name: 'blue' }
                          ] }
                        ] }
                      ] },
                      { name: 'foregroundColor', type: 'object', properties: [
                        { name: 'color', type: 'object', properties: [
                          { name: 'rgbColor', type: 'object', properties: [
                            { name: 'red' },
                            { name: 'green' },
                            { name: 'blue' }
                          ] }
                        ] }
                      ] },
                      { name: 'fontSize', type: 'object',
                        properties: [
                          { name: 'magnitude', control_type: 'number', type: 'number' },
                          { name: 'unit' }
                        ] },
                      { name: 'weightedFontFamily', type: 'object',
                        properties: [
                          { name: 'fontFamily' },
                          { name: 'weight', control_type: 'number', type: 'number' }
                        ] },
                      { name: 'baselineOffset' }
                    ] },
                  { name: 'paragraphStyle', type: 'object',
                    properties: [
                      { name: 'namedStyleType' },
                      { name: 'alignment' },
                      { name: 'lineSpacing', control_type: 'number', type: 'number' },
                      { name: 'direction' },
                      { name: 'spacingMode' },
                      { name: 'spaceAbove', type: 'object', properties: [
                        { name: 'unit' }
                      ] },
                      { name: 'spaceBelow', type: 'object', properties: [
                        { name: 'unit' }
                      ] },
                      { name: 'borderBetween', type: 'object',
                        properties: [
                          { name: 'color', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'width', type: 'object', properties: [
                            { name: 'unit' }
                          ] },
                          { name: 'padding', type: 'object', properties: [
                            { name: 'unit' }
                          ] },
                          { name: 'dashStyle' }
                        ] },
                      { name: 'borderTop', type: 'object',
                        properties: [
                          { name: 'color', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'width', type: 'object', properties: [
                            { name: 'unit' }
                          ] },
                          { name: 'padding', type: 'object', properties: [
                            { name: 'unit' }
                          ] },
                          { name: 'dashStyle' }
                        ] },
                      { name: 'borderBottom', type: 'object',
                        properties: [
                          { name: 'color', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'width', type: 'object', properties: [
                            { name: 'unit' }
                          ] },
                          { name: 'padding', type: 'object', properties: [
                            { name: 'unit' }
                          ] },
                          { name: 'dashStyle' }
                        ] },
                      { name: 'borderLeft', type: 'object',
                        properties: [
                          { name: 'color', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'width', type: 'object', properties: [
                            { name: 'unit' }
                          ] },
                          { name: 'padding', type: 'object', properties: [
                            { name: 'unit' }
                          ] },
                          { name: 'dashStyle' }
                        ] },
                      { name: 'borderRight', type: 'object',
                        properties: [
                          { name: 'color', type: 'object', properties: [
                            { name: 'color', type: 'object', properties: [
                              { name: 'rgbColor', type: 'object', properties: [
                                { name: 'red' },
                                { name: 'green' },
                                { name: 'blue' }
                              ] }
                            ] }
                          ] },
                          { name: 'width', type: 'object', properties: [
                            { name: 'unit' }
                          ] },
                          { name: 'padding', type: 'object', properties: [
                            { name: 'unit' }
                          ] },
                          { name: 'dashStyle' }
                        ] },
                      { name: 'indentFirstLine', type: 'object', properties: [
                        { name: 'unit' }
                      ] },
                      { name: 'indentStart', type: 'object', properties: [
                        { name: 'unit' }
                      ] },
                      { name: 'indentEnd', type: 'object', properties: [
                        { name: 'unit' }
                      ] },
                      { name: 'keepLinesTogether', type: 'boolean' },
                      { name: 'keepWithNext', type: 'boolean' },
                      { name: 'avoidWidowAndOrphan', type: 'boolean' },
                      { name: 'shading', type: 'object',
                        properties: [
                          { name: 'backgroundColor', type: 'object',
                            properties: [
                              { name: 'color', type: 'object', properties: [
                                { name: 'rgbColor', type: 'object', properties: [
                                  { name: 'red' },
                                  { name: 'green' },
                                  { name: 'blue' }
                                ] }
                              ] }
                            ] }
                        ] }
                    ] }
                ]
              }
            ] },
          { name: 'revisionId' },
          { name: 'suggestionsViewMode' }
        ]
      end
    },
    update_response: {
      fields: lambda do
        [
          { name: 'documentId' },
          { name: 'replies', type: 'array', of: 'object', properties: [
            { name: 'replaceAllText', type: 'object', properties: [
              { name: 'occurrencesChanged', control_type: 'number', type: 'number' }
            ] }
          ] },
          { name: 'writeControl', type: 'object', properties: [
            { name: 'requiredRevisionId' }
          ] },
          { name: 'doc_url' }
        ]
      end
    }
  },
  actions: {
    custom_action: {
      deprecated: true,
      subtitle: 'Build your own Google Docs action with a HTTP request',

      description: lambda do |object_value, _object_label|
        "<span class='provider'>" \
        "#{object_value[:action_name] || 'Custom action'}</span> in " \
        "<span class='provider'>Google Docs</span>"
      end,

      help: {
        body: 'Build your own Google Docs action with a HTTP request. ' \
        'The request will be authorized with your Google Docs connection.'
      },

      config_fields: [
        {
          name: 'action_name',
          hint: "Give this action you're building a descriptive name, e.g. " \
          'create record, get record',
          default: 'Custom action',
          optional: false,
          schema_neutral: true
        },
        {
          name: 'verb',
          label: 'Method',
          hint: 'Select HTTP method of the request',
          optional: false,
          control_type: 'select',
          pick_list: %w[get post put patch options delete].map { |verb| [verb.upcase, verb] }
        }
      ],

      input_fields: lambda do |object_definition|
        object_definition['custom_action_input']
      end,

      execute: lambda do |_connection, input, input_schema|
        verb = input['verb']
        if %w[get post put patch options delete].exclude?(verb)
          error("#{verb.upcase} not supported")
        end
        path = input['path']
        data = call('format_payload', input.dig('input', 'data') || {})
        data_schema = input_schema&.only('input')&.dig(0, 'properties')&.
          only('data')&.dig(0, 'properties')
        _dummy_schema = data_schema&.each do |field|
          if field.dig('details', 'primitive_array')
            prim_array_name = field.dig('details', 'real_name')
            data[prim_array_name] = data[prim_array_name]&.pluck('value')
          end
        end
        if input['request_type'] == 'multipart'
          data = data.each_with_object({}) do |(key, val), hash|
            hash[key] = if val.is_a?(Hash)
                          [val[:file_content],
                           val[:content_type],
                           val[:original_filename]]
                        else
                          val
                        end
          end
        end
        request_headers = input['request_headers']&.each_with_object({}) do |item, hash|
          hash[item['key']] = item['value']
        end || {}
        request = case verb
                  when 'get'
                    get(path, data)
                  when 'post'
                    if input['request_type'] == 'raw'
                      post(path).request_body(data)
                    else
                      post(path, data)
                    end
                  when 'put'
                    if input['request_type'] == 'raw'
                      put(path).request_body(data)
                    else
                      put(path, data)
                    end
                  when 'patch'
                    if input['request_type'] == 'raw'
                      patch(path).request_body(data)
                    else
                      patch(path, data)
                    end
                  when 'options'
                    options(path, data)
                  when 'delete'
                    delete(path, data)
                  end.headers(request_headers)
        request = case input['request_type']
                  when 'url_encoded_form'
                    request.request_format_www_form_urlencoded
                  when 'multipart'
                    request.request_format_multipart_form
                  else
                    request
                  end
        response =
          if input['response_type'] == 'raw'
            request.response_format_raw
          else
            request
          end.after_error_response(/.*/) do |code, body, headers, message|
            error({ code: code, message: message, body: body, headers: headers }.to_json)
          end

        response.after_response do |_code, res_body, res_headers|
          {
            body: res_body ? call('format_response', res_body) : nil,
            headers: res_headers
          }
        end
      end,

      output_fields: lambda do |object_definition|
        object_definition['custom_action_output']
      end
    },
    create_document: {
      title: 'Create document',
      subtitle: 'Create new document in Google Docs.',
      description: "Create <span class='provider'>document</span> in " \
      "<span class='provider'>Google Docs</span>",
      help: 'Creates a new document with the provided text in a simple paragraph format.',

      input_fields: lambda do |object_definitions|
        object_definitions['create_document_input']
      end,

      execute: lambda do |_connection, input|
        ## CREATE A BLANK DOCUMENT
        document = post('documents', input.except('body')).
                   after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end
        content = [
          insertText: {
            text: input['body'],
            location: {
              index: 1
            }
          }
        ]
        ## UPDATE THE DOCUMENT WITH PARAGRAPH CONTENT
        created_document = post("documents/#{document['documentId']}:batchUpdate").
                           payload(requests: content).
                           after_error_response(/.*/) do |_code, body, _header, message|
                             error("#{message}: #{body}")
                           end
        ## RETRIEVE DOCUMENT PROPERTIES
        get("documents/#{created_document['documentId']}").
          after_error_response(/.*/) do |_code, body, _header, message|
            error("#{message}: #{body}")
          end
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['document']
      end,

      sample_output: lambda do |_connection|
        call('get_sample_output', { 'object' => 'document' })
      end
    },
    create_document_from_template: {
      title: 'Create document from template',
      subtitle: 'Create document from template in Google Docs.',
      description: "Create <span class='provider'>document from template</span> in " \
      "<span class='provider'>Google Docs</span>",
      help: 'Creates a new document from an existing template',

      input_fields: lambda do |object_definitions|
        object_definitions['create_document_from_template_input']
      end,

      execute: lambda do |_connection, input|
        fields_to_change = input['fields']&.map do |key, value|
          {
            'replaceAllText' => {
              'containsText' => {
                'text' => "{{#{key}}}",
                'matchCase' => true
              },
              'replaceText' => value
            }
          }
        end

        document = post("https://www.googleapis.com/drive/v3/files/#{input['id']}/copy").
                   after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end

        revision_id = get("documents/#{document['id']}").
                      after_error_response(/.*/) do |_code, body, _header, message|
                        error("#{message}: #{body}")
                      end&.[]('revisionId')

        payload = { requests: fields_to_change,
                    writeControl: {
                      targetRevisionId: revision_id
                    } }
        response = post("documents/#{document['id']}:batchUpdate", payload).
                   after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end
        replaced = get("documents/#{response['documentId']}").
                   after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end

        update_requests = []

        input['fields']&.each do |_key, value|
          replaced&.dig('body', 'content')&.each do |content|
            content&.dig('paragraph', 'elements')&.each do |element|
              if element&.dig('textRun', 'content')&.include?(value)
                start_index = element['startIndex'] + element.dig('textRun', 'content').index(value)
                end_index = start_index + value.length

                text_style = {
                  updateTextStyle: {
                    range: {
                      startIndex: start_index,
                      endIndex: end_index
                    },
                    textStyle: input['text_style'],
                    fields: input['text_style']&.map do |style_key, style_value|
                      style_key if style_value.present?
                    end&.compact&.join(',')
                  }
                }

                update_requests << text_style
              end
            end
          end
        end

        if update_requests.any?
          style_payload = {
            requests: update_requests,
            writeControl: {
              targetRevisionId: replaced&.[]('revisionId')
            }
          }

          final = post("documents/#{response['documentId']}:batchUpdate", style_payload).
                  after_error_response(/.*/) do |_code, body, _header, message|
                    error("#{message}: #{body}")
                  end

          get("documents/#{final['documentId']}").
            after_error_response(/.*/) do |_code, body, _header, message|
              error("#{message}: #{body}")
            end
        else
          replaced
        end
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['create_document_from_template_output']
      end,
      sample_output: lambda do |_connection|
        call('get_sample_output', { 'object' => 'document' })
      end
    },
    get_document: {
      title: 'Get document',
      subtitle: 'Retrieves the latest version of the specified document.',
      description: "Get <span class='provider'>document</span> in " \
      "<span class='provider'>Google Docs</span>",
      input_fields: lambda do |_object_definitions|
        [{ name: 'document_id', optional: false }]
      end,
      execute: lambda do |_connection, input|
        get("documents/#{input['document_id']}")
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['document']
      end,
      sample_output: lambda do |_connection, _input|
        call('get_sample_output', { 'object' => 'document' })
      end
    },
    update_document: {
      title: 'Update document',
      subtitle: 'Replaces all instances of text matching a criteria with replace text.',
      description: "Update <span class='provider'>document</span> in " \
      "<span class='provider'>Google Docs</span>",
      input_fields: lambda do |object_definitions|
        [
          { name: 'document_id', optional: false },
          { name: 'requests',
            optional: false,
            type: :array,
            of: :object,
            properties: object_definitions['replace_all_text'] }
        ]
      end,
      execute: lambda do |_connection, input|
        input['writeControl'] = {
          targetRevisionId: get("documents/#{input['document_id']}")['revisionId']
        }
        response = post("documents/#{input['document_id']}:batchUpdate", input)
        response['doc_url'] = "https://docs.google.com/document/d/#{response['documentId']}/edit?usp=drivesdk"
        response
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['update_response']
      end,
      sample_output: lambda do |_connection, _input|
        {
          replies: [
            {
              replaceAllText: {
                occurrencesChanged: 3
              }
            }
          ],
          writeControl: {
            requiredRevisionId: 'ALm37BVLHTiiD0OLBUsf0fc08b01YKmAFdn9S3s2Wast8J36dn8dRS1XM...'
          },
          documentId: '14qyjH2fd11C84UmmrpU9aQsk5ZheusrnMV6vwducg0s',
          doc_url: 'https://docs.google.com/document/d/14qyjH2fd11C84rpU9aZQX5ZheusrnMV6vwducg0s/edit?usp=drivesdk'
        }
      end
    }
  }
}