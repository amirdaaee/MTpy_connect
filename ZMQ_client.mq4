//+------------------------------------------------------------------+
//|                                                           AI.mq4 |
//|                        Copyright 2019, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2019, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#property tester_library "libzmq.dll"
#property tester_library "libsodium.dll"

#include <Zmq/Zmq.mqh>
#include <JAson.mqh>
#include <TradeManager.mqh>

input string HOSTNAME="127.0.0.1";
input int PORT=5556;
input string ZEROMQ_PROTOCOL="tcp";
input int PULLTIMEOUT=500;
input int LASTBARSCOUNT=48;
input int MagicNumber=123456;
input bool TickEvent = False;

const string PROJECT_NAME="ZMQ_client";
const string Version = "MT4";
string ServerLastMsg = "";
//+------------------------------------------------------------------+
Context context(PROJECT_NAME);
Socket socket(context,ZMQ_REQ);
//+------------------------------------------------------------------+
//| events handler
//+------------------------------------------------------------------+
int OnInit()
  {
//--- socket connection
   socket.setLinger(0);
   socket.connect(StringFormat("%s://%s:%d",ZEROMQ_PROTOCOL,HOSTNAME,PORT));
   context.setBlocky(false);
//--- send init request to server
   CJAVal req_json;
   req_json["event"]="init";
   req_json["args"]["symbol"]=Symbol();
   req_json["args"]["version"]=Version;
   req_json["args"]["magic"]=MagicNumber;
   GetOrders(req_json);
   GetLastBars(req_json, LASTBARSCOUNT);
   SendRequest(req_json);
   
   if(ServerLastMsg == "error" || ServerLastMsg == "empty")
     {
      return(-1);
     }
//--- create timer
//EventSetMillisecondTimer(TIMER);
   Print("initialization success");
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- destroy timer
//EventKillTimer();
//--- send deinit request to server
   CJAVal req_json;
   req_json["event"]="deinit";
   req_json["args"]["magic"]=MagicNumber;
   SendRequest(req_json);
//--- Shutdown ZeroMQ Context
   context.shutdown();
   Print("ZMQ context shutdown");
  }
//+------------------------------------------------------------------+
void OnTick()
  {
   static datetime lastbar;
   datetime curbar = Time[0];
   if(lastbar!=curbar)
     {
      lastbar=curbar;
      OnNewBar();
     }
   TradeManager::Run();
   if(TickEvent)
     {
      OnTickEvent();
     }
  }
//+------------------------------------------------------------------+
void OnTickEvent()
  {
   Print("tick");
   CJAVal req_json;
   req_json["event"]="tick";
   req_json["args"]["magic"]=MagicNumber;
   req_json["args"]["ask"]=Ask;
   req_json["args"]["bid"]=Bid;
   SendRequest(req_json);
  }
//+------------------------------------------------------------------+
void OnNewBar()
  {
   static bool frist_run=True;
   if(frist_run)
     {
      frist_run = False;
      return;
     }
   Print("new bar");
   CJAVal req_json;
   req_json["event"]="newbar";
   GetLastBars(req_json, 1);
   SendRequest(req_json);
  }
//+------------------------------------------------------------------+
void OnTrade()
  {
   static bool frist_run=True;
   if(frist_run)
     {
      frist_run = False;
      return;
     }
   Print("trade");
   CJAVal req_json;
   req_json["event"]="trade";
   GetOrders(req_json);
   SendRequest(req_json);
  }
//+------------------------------------------------------------------+
//| Request fullfil
//| *** all data for current symbol only
//+------------------------------------------------------------------+
void GetOrders(CJAVal &js_ret)
  {
   int c_pending=0;
   int c_opened=0;
   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
        {
         if(OrderSymbol()!=_Symbol)
           {
            continue;
           }
         if(OrderType() == OP_BUY || OrderType() == OP_SELL)
           {
            js_ret["args"]["position"][c_opened]["Ticket"]=IntegerToString(OrderTicket());
            js_ret["args"]["position"][c_opened]["Type"]=OrderTypeToString(OrderType());
            js_ret["args"]["position"][c_opened]["Magic"]=IntegerToString(OrderMagicNumber());
            js_ret["args"]["position"][c_opened]["Volume"]=DoubleToString(OrderLots());
            js_ret["args"]["position"][c_opened]["Price"]=DoubleToString(OrderOpenPrice());
            js_ret["args"]["position"][c_opened]["SL"] = DoubleToString(OrderStopLoss());
            js_ret["args"]["position"][c_opened]["TP"] = DoubleToString(OrderTakeProfit());
            js_ret["args"]["position"][c_opened]["Profit"]=DoubleToString(OrderProfit());
            c_opened++;
           }
         else
           {
            js_ret["args"]["order"][c_pending]["Ticket"]=IntegerToString(OrderTicket());
            js_ret["args"]["order"][c_pending]["Type"]=OrderTypeToString(OrderType());
            js_ret["args"]["order"][c_pending]["Magic"]=IntegerToString(OrderMagicNumber());
            js_ret["args"]["order"][c_pending]["Volume"]=DoubleToString(OrderLots());
            js_ret["args"]["order"][c_pending]["Price"]=DoubleToString(OrderOpenPrice());
            js_ret["args"]["order"][c_pending]["SL"] = DoubleToString(OrderStopLoss());
            js_ret["args"]["order"][c_pending]["TP"] = DoubleToString(OrderTakeProfit());
            c_pending++;
           }
        }
     }
   if(c_opened==0)
     {
      js_ret["args"]["position"]="null";
     }
   if(c_pending==0)
     {
      js_ret["args"]["order"]="null";
     }
  }
//+------------------------------------------------------------------+
void GetLastBars(CJAVal &js_ret, int m_Bars)
  {
   MqlRates rates_array[];
   int rates_count=CopyRates(Symbol(),Period(),1,m_Bars,rates_array);
   if(rates_count>0)
     {
      for(int i=0; i<rates_count; i++)
        {
         js_ret["args"]["dataset"][i]["DateTime"]=TimeToString(rates_array[i].time);
         js_ret["args"]["dataset"][i]["Open"]=DoubleToString(rates_array[i].open);
         js_ret["args"]["dataset"][i]["High"]=DoubleToString(rates_array[i].high);
         js_ret["args"]["dataset"][i]["Low"]=DoubleToString(rates_array[i].low);
         js_ret["args"]["dataset"][i]["Close"]=DoubleToString(rates_array[i].close);
         js_ret["args"]["dataset"][i]["Volume_tick"]=DoubleToString(rates_array[i].tick_volume);
         js_ret["args"]["dataset"][i]["Volume_real"]=DoubleToString(rates_array[i].real_volume);
         js_ret["args"]["dataset"][i]["Spread"]=IntegerToString(rates_array[i].spread);
        }
     }
   else
     {
      js_ret["args"]["data"]="null";
     }
  }
//+------------------------------------------------------------------+
//| Requesting
//+------------------------------------------------------------------+
void SendRequest(CJAVal &req_json)
  {
   req_json["magic"]=IntegerToString(MagicNumber);
   string req_context="";
   req_json.Serialize(req_context);
   ZmqMsg request(req_context);
   socket.send(request);
   GetResponse();
  }
//+------------------------------------------------------------------+
//| Response handle
//+------------------------------------------------------------------+
void GetResponse()
  {
   CJAVal resp_json;
   ZmqMsg message;
   PollItem items[1];
   socket.fillPollItem(items[0],ZMQ_POLLIN);
   Socket::poll(items,PULLTIMEOUT);
//--- empty response handler
   if(items[0].hasInput())
     {
      socket.recv(message);
      resp_json.Deserialize(message.getData());
      ResponseParse(resp_json);
     }
   else
     {
      Print("no response from server");
      ServerLastMsg = "empty";
     }
  }
//+------------------------------------------------------------------+
void ResponseParse(CJAVal &resp_json)
  {
   string resptype = resp_json["type"].ToStr();
   if(resptype=="action")
      WhichAction(resp_json);
   else
      if(resptype=="message")
         WhichMessage(resp_json);
      else
         PrintFormat("resptype not understood (%s)",resptype);
  }
//+------------------------------------------------------------------+
void WhichAction(CJAVal &resp_json)
  {
   string command=resp_json["command"].ToStr();
   if(command=="position_open")
      PositionOpen(resp_json);
   else
      if(command=="position_modify")
        {
         PositionModify(resp_json);
        }
      else
         if(command=="position_close")
           {
            PositionClose(resp_json);
           }
         else
            if(command == "sync")
              {
               SyncDB();
              }
            else
              {
               PrintFormat("command not understood (%s)",command);
              }
  }
//+------------------------------------------------------------------+
void WhichMessage(CJAVal &resp_json)
  {
   string command=resp_json["command"].ToStr();
   Print("server message:",command);
   ServerLastMsg=command;
  }
//+------------------------------------------------------------------+
//| Action
//+------------------------------------------------------------------+
void PositionOpen(CJAVal &resp_json)
  {
   Print("Position open request");
   string ordertype_s;
   int ordertype;
   double volume;
   double sl;
   double tp;
   string comment;
   double price;
   color OrderColor;

   for(int i=0; i<resp_json["args"]["orderlist"].Size(); i++)
     {
      ordertype_s=resp_json["args"]["orderlist"][i]["type"].ToStr();
      ordertype=StringToOrderType(ordertype_s);
      volume=resp_json["args"]["orderlist"][i]["volume"].ToDbl();
      sl= resp_json["args"]["orderlist"][i]["sl"].ToDbl();
      tp= resp_json["args"]["orderlist"][i]["tp"].ToDbl();
      comment = resp_json["args"]["orderlist"][i]["cm"].ToStr();

      switch(ordertype)
        {
         case OP_BUY:
           {
            OrderColor = clrGreen;
            price= Ask;
            break;
           }
         case OP_SELL:
           {
            OrderColor = clrRed;
            price= Bid;
            break;
           }
         default:
           {
            PrintFormat("OrderType not found (%s)",ordertype_s);
            continue;
           }
        }
      int status = OrderSend(Symbol(), ordertype, volume, price, 100, sl, tp, comment, MagicNumber, 0, OrderColor) ;
      if(status!=-1)
        {
         PrintFormat("%s %f %f %f : Order done",ordertype_s,volume,sl,tp);
        }
      else
        {
         PrintFormat("%s %f %f %f : Order fail (code : %d)",ordertype_s,volume,sl,tp,GetLastError());
        }
     }
  }
//+------------------------------------------------------------------+
void PositionModify(CJAVal &resp_json)
  {
   Print("Position modify request");
   int ticket;
   double sl;
   double tp;

   for(int i=0; i<resp_json["args"]["modifylist"].Size(); i++)
     {
      ticket=resp_json["args"]["modifylist"][i]["ticket"].ToInt();
      if(!OrderSelect(ticket,SELECT_BY_TICKET))
        {
         PrintFormat("ticket %d not found",ticket);
         continue;
        }
      sl= resp_json["args"]["modifylist"][i]["sl"].ToDbl();
      tp= resp_json["args"]["modifylist"][i]["tp"].ToDbl();
      if(sl == -1)
        {
         sl = OrderStopLoss();
        }
      if(tp== -1)
        {
         tp = OrderTakeProfit();
        }
      bool status = OrderModify(OrderTicket(),OrderOpenPrice(),sl,tp,OrderExpiration()) ;
      if(status==true)
        {
         PrintFormat("%d : Position modify done",ticket);
        }
      else
        {
         PrintFormat("%d : Position modify fail (code : %d)",ticket,GetLastError());
        }
     }
  }
//+------------------------------------------------------------------+
void PositionClose(CJAVal &resp_json)
  {
   Print("Position close request");
   int ticket;
   string ordertype_s;
   int ordertype;
   double price;
   color OrderColor;

   for(int i=0; i<resp_json["args"]["ticketlist"].Size(); i++)
     {
      ticket = resp_json["args"]["ticketlist"][i].ToInt();
      if(!OrderSelect(ticket,SELECT_BY_TICKET))
        {
         PrintFormat("ticket %d not found",ticket);
         continue;
        }
      ordertype=OrderType();
      ordertype_s = OrderTypeToString(ordertype);

      switch(ordertype)
        {
         case OP_BUY:
           {
            OrderColor = clrRed;
            price= Bid;
            break;
           }
         case OP_SELL:
           {
            OrderColor = clrGreen;
            price= Ask;
            break;
           }
         default:
           {
            PrintFormat("OrderType not found (%s)",ordertype_s);
            continue;
           }
        }
      bool status = OrderClose(ticket,OrderLots(),price,100,OrderColor);
      if(status==true)
        {
         PrintFormat("%d : Position close done",ticket);
        }
      else
        {
         PrintFormat("%d : Position close fail (code : %d)",ticket,GetLastError());
        }
     }
  }
//+------------------------------------------------------------------+
void SyncDB()
  {
   CJAVal req_json;
   req_json["event"]="sync";
   GetOrders(req_json);
   GetLastBars(req_json, LASTBARSCOUNT);
   SendRequest(req_json);
  }
//+------------------------------------------------------------------+
//helpers
//+------------------------------------------------------------------+
string OrderTypeToString(int otype)
  {
   switch(otype)
     {
      case OP_BUY:
         return "OP_BUY";
      case OP_SELL:
         return "OP_SELL";
      case OP_BUYLIMIT:
         return "OP_BUYLIMIT";
      case OP_SELLLIMIT:
         return "OP_SELLLIMIT";
      case OP_BUYSTOP:
         return "OP_BUYSTOP";
      case OP_SELLSTOP:
         return "OP_SELLSTOP";
     }
   return "";
  }
//+------------------------------------------------------------------+
int  StringToOrderType(string otype)
  {
   if(otype == "OP_BUY")
      return OP_BUY;
   if(otype == "OP_SELL")
      return OP_SELL;
   if(otype == "OP_BUYLIMIT")
      return OP_BUYLIMIT;
   if(otype == "OP_SELLLIMIT")
      return OP_SELLLIMIT;
   if(otype == "OP_BUYSTOP")
      return OP_BUYSTOP;
   if(otype == "OP_SELLSTOP")
      return OP_SELLSTOP;
   return -1;
  }
//+------------------------------------------------------------------+
