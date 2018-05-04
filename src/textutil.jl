function adagram_isblank(c::Char)
  return c == ' ' || c == '\t'
end

function adagram_isblank(s::AbstractString)
  return all((c->begin
            c == ' ' || c == '\t'
        end),s)
end

function word_iterator(f::IO, end_pos::Int64=-1)
  function producer()
    while (end_pos < 0 || position(f) < end_pos) && !eof(f)
      w = readuntil(f, ' ')
      if length(w) < 1 break end
      w = w[1:end-1]
      if !adagram_isblank(w)
        produce(w)
      end
    end
  end

  return Task(producer)
end

function looped_sent_iterator(f::IO, start_pos::Int64, end_pos::Int64)
  function producer()
    while true
      try
        s = readuntil(f, '\n')
        if length(s) < 1 break end
        s = s[1:end-1]
        if !adagram_isblank(s)
          produce(s)
        end
        if position(f) >= end_pos seek(f, start_pos) end
      catch UnicodeError
      end
    end
  end

  return Task(producer)
end

function count_words(f::IOStream, min_freq::Int=5)
  counts = Dict{AbstractString, Int64}()

  for word in word_iterator(f)
    if get(counts, word, 0) == 0
      counts[word] = 1
    else
      counts[word] += 1
    end
  end

  for word in [keys(counts)...]
    if counts[word] < min_freq
      delete!(counts, word)
    end
  end

  V = length(counts)
  id2word = Array(AbstractString, V)
  freqs = zeros(Int64, V)
  i = 1
  for (word, count) in counts
    id2word[i] = word
    freqs[i] = count
    i += 1
  end

  return freqs, id2word
end

function align(f::IO)
  while !adagram_isblank(read(f, Char))
    continue
  end

  while adagram_isblank(read(f, Char))
    continue
  end

  seek(f, position(f)-1)
end

function read_words(f::IO,
    dict::Dictionary, doc::DenseArray{Int32},
    batch::Int, last_pos::Int)
  words = word_iterator(f, last_pos)
  i = 1
  for j in 1:batch
    word = consume(words)
    id = get(dict.word2id, word, -1)
    if id == -1
      continue
    end

    doc[i] = id
    i += 1
  end

  return view(doc, 1:i-1)
end

function read_words(str::AbstractString,
    dict::Dictionary, doc::DenseArray{Int32},
    batch::Int, last_pos::Int)
  i = 1
  for word in split(str, ' ')
    id = get(dict.word2id, word, -1)
    if id == -1
      continue
    end

    doc[i] = id
    i += 1
  end

  return view(doc, 1:i-1)
end

# modified to return nested Arrays containing the ids of words in
# the sentences, one sentence per Array
function read_words(f::IOStream, start_pos::Int64, end_pos::Int64,
    dict::Dictionary, doc::DenseArray{Int32},
    freqs::DenseArray{Int64}, threshold::Float64,
    words_read::DenseArray{Int64}, total_words::Float64)
  sentences = looped_sent_iterator(f, start_pos, end_pos)
  i = 1
  sentences_ids = []
  num_sentences = 0
  while i <= length(doc) && words_read[1] < total_words
    sent_ids = Int32[]
    sentence = consume(sentences)
    for word in split(sentence)
      id = get(dict.word2id, word, -1)
      if id == -1
        continue
      elseif rand() < 1. - sqrt(threshold / (freqs[id] / total_words))
        words_read[1] += 1
        continue
      end
      push!(sent_ids, id)
      i += 1
    end

    if length(sent_ids) > 0
      push!(sentences_ids, sent_ids)
      num_sentences += 1
    else
      println("Skipped sentence with no valid words: ", sentence)
    end
  end

  return sentences_ids
  #return view(sentences_ids, 1:num_sentences-1)
end
